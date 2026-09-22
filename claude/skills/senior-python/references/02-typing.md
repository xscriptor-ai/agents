# Typing and Runtime Validation

Static typing contracts with pyright/mypy plus runtime validation with pydantic v2: strict setups, Protocols, PEP 695/696 generics, TypedDict/Unpack, overloads, exhaustiveness, and escape-hatch policy.

## Checker Setup

```toml
# pyproject.toml
[tool.mypy]
python_version = "3.13"
strict = true
warn_unreachable = true
enable_error_code = ["redundant-expr", "truthy-bool", "ignore-without-code"]
plugins = ["pydantic.mypy"]

[tool.pyright]
pythonVersion = "3.13"
typeCheckingMode = "strict"
reportMissingTypeStubs = "warning"
reportUnnecessaryTypeIgnoreComment = true
```

- `strict = true` flips on `disallow_untyped_defs`, `disallow_any_generics`,
  `warn_return_any`, `no_implicit_optional`, and friends. Adopt per-module with
  `[[tool.mypy.overrides]]` instead of weakening the global config.
- pyright's `strict` is the stricter of the two on narrowing and generics; running both in
  CI is common for libraries. Run one as the gate and the other as advisory if CI time
  matters.
- Type-check `src/` and `tests/` separately: `mypy src` with strict, `mypy tests` with
  relaxed `disallow_untyped_defs` if fixtures fight the checker.
- `--strict` failures are cheaper to prevent than to retrofit; if adopting on an existing
  repo, create a baseline and ratchet (allowlist failing modules, then burn it down).
- Do not type-check with `python_version` older than `requires-python`; that silently
  approves APIs the runtime does not have.

## Protocols vs ABCs

```python
from typing import Protocol

class Clock(Protocol):
    def now(self) -> float: ...

def elapsed(clock: Clock, started: float) -> float:
    return clock.now() - started
```

- Protocols are structural: any object with a compatible `now` satisfies `Clock`, no
  inheritance required. Prefer them for dependencies you cannot edit.
- ABCs are nominal: subclassing is explicit and gives `register()` and shared
  implementations. Prefer them when you own the hierarchy and want default behavior.
- Variance: read-only protocols are naturally covariant; a method parameter position makes
  it contravariant. Let the checker infer and do not fight it with `TypeVar`.
- `@runtime_checkable` only supports `isinstance` checks that verify member presence, not
  signatures. Use it sparingly; it is not a validation mechanism.
- Keep protocols small (one or two methods). Fat protocols are hard to fake in tests and
  tend to mirror concrete classes.

**Anti-patterns**

- `isinstance(x, Protocol)` as a substitute for pydantic validation.
- Inheriting from a Protocol to "implement" it; structural satisfaction is enough.
- Protocols with `__init__` — instantiation shape is not part of the contract.

## Generics: PEP 695 and Defaults

```python
from collections.abc import Iterable, Iterator

def chunked[T](items: Iterable[T], size: int) -> Iterator[list[T]]:
    batch: list[T] = []
    for item in items:
        batch.append(item)
        if len(batch) == size:
            yield batch
            batch = []

class Repo[ModelT: BaseModel]:  # bound keeps members typed
    def __init__(self, model: type[ModelT]) -> None:
        self.model = model

    def parse(self, raw: bytes) -> ModelT:
        return self.model.model_validate_json(raw)

class Cache[K, V = str]:  # PEP 696 default (3.13+)
    ...
```

- Bounds (`T: BaseModel`) are usually better than constraints (`T: (int, str)`); constraints
  collapse the type to the union.
- PEP 696 type defaults let callers omit parameters (`class Response[DataT = dict]`) while
  libraries keep full genericity. On 3.12 use `typing_extensions.TypeVar(default=...)`;
  `NoDefault` marks "no default".
- Type aliases: `type Json = dict[str, "Json"] | list["Json"] | str | int | float | bool | None`.
- Variadic tuples: `def head[*Ts](*args: *Ts) -> tuple[*Ts]`; useful for wrappers.
- Runtime access to type parameters is limited; for runtime generics use pydantic
  `TypeAdapter(Repo[User])` or `typing.get_args`.

**Anti-patterns**

- Unbounded `T` used as `T()` or `T.from_x()`; the checker cannot prove constructibility.
- Hand-written variance annotations on mutable containers, which are invariant by design.
- Replacing a plain function with a generic abstract class before there are two use cases.

## ParamSpec and Concatenate

```python
from collections.abc import Callable
from functools import wraps
from typing import ParamSpec

P = ParamSpec("P")

def logged[**P, R](fn: Callable[P, R]) -> Callable[P, R]:
    @wraps(fn)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        return fn(*args, **kwargs)
    return wrapper
```

- PEP 695 syntax spells `ParamSpec` as `**P`; `Concatenate[Request, **P]` models decorators
  that inject a leading argument (for example auth dependencies).
- Always pair `*args: P.args` with `**kwargs: P.kwargs` in the same signature.
- `functools.wraps` preserves `__name__`; it does not preserve types, so the callable
  signature must be expressed in annotations.

## TypedDict, Unpack, and ReadOnly

```python
from typing import NotRequired, ReadOnly, TypedDict, Unpack

class Job(TypedDict):
    id: str
    tags: ReadOnly[list[str]]
    retry: NotRequired[int]

class Empty(TypedDict, total=False):
    ...

def run(job: Job, **opts: Unpack[Empty]) -> None:
    print(job["id"])
```

- `total=False` makes all keys optional; `Required[...]` marks mandatory ones inside a
  partial TypedDict. Prefer explicit `NotRequired` on a total TypedDict for readability.
- `ReadOnly[T]` (3.13+, `typing_extensions` earlier) stops mutation through the typed view.
- `Unpack[TypedDict]` types `**kwargs` precisely; use it for option bags instead of
  `**kwargs: Any`.
- Closed TypedDicts with `closed=True` / `extra_items=` (PEP 728) are available in
  `typing_extensions` and rolling into newer CPython — verify upstream before relying on it
  in libraries.
- TypedDict is for static shapes (JSON payloads, kwargs); it performs no runtime
  validation. Parse with pydantic if the data is external.

**Anti-patterns**

- `def f(**kwargs: Any)` for anything with a known option set.
- Mutating a TypedDict key typed `ReadOnly`.
- Using TypedDict as an ORM/model class with methods; it is a dict shape.

## Overloads

```python
from typing import Literal, overload

@overload
def parse(value: str) -> int: ...
@overload
def parse(value: bytes) -> str: ...
def parse(value: str | bytes) -> int | str:
    if isinstance(value, bytes):
        return value.decode()
    return int(value)
```

- The implementation signature stays untyped for callers (no `@overload`), and must accept
  every overload's inputs.
- Prefer `Literal` mode flags over parallel functions; overloads shine for return-type
  dependence on input type.
- Avoid calling an overloaded function from inside its own implementation; the checker
  sees only overloads there. Delegate to a private `_parse_impl`.
- Overloads are checked for overlap; unreachable or ambiguous overloads are reported under
  `enable_error_code`/`reportOverlappingOverload`.

## Self, Exhaustiveness, LiteralString

```python
from enum import Enum, auto
from typing import LiteralString, Self, assert_never

class Builder:
    def with_name(self, name: str) -> Self:
        self._name = name
        return self

class Mode(Enum):
    READ = auto()
    WRITE = auto()

def mode_flag(mode: Mode) -> str:
    match mode:
        case Mode.READ:
            return "r"
        case Mode.WRITE:
            return "w"
        case _:
            assert_never(mode)

def run_query(sql: LiteralString) -> None: ...

run_query("select 1")          # ok
user_input: str = input()
run_query(user_input)          # checker error: possible injection
```

- `Self` (3.11+) types fluent APIs and `__enter__` without repeating the class name.
- `assert_never` turns the default branch into an exhaustiveness proof and a runtime tripwire
  when a new enum member lands; keep `match` and `if/elif` totals.
- `LiteralString` flows through f-strings and `str.join` but not through arbitrary `str`
  input; use it on SQL/shell/template sinks to make injection a type error.
- `TypeIs` (3.13+) narrows both branches like `isinstance`, unlike `TypeGuard`, which only
  narrows the positive branch. Use `TypeIs` for predicates that return `bool`.

## typing_extensions Policy

| Need | Use |
|---|---|
| Feature in the project's floor version | `typing` from stdlib |
| Supporting older majors | `typing_extensions` |
| Preview features not yet in any stable CPython | `typing_extensions` behind a comment |
| `deprecated` (PEP 702), `Doc`, `TypeForm`, `NoDefault`, `ReadOnly`, `TypeIs` | `typing_extensions` on old floors, stdlib when available |

- Depend on `typing_extensions` explicitly; never rely on it arriving transitively.
- Pin a floor that contains the symbol you use and watch upstream removals of pre-release
  aliases. Type-only imports belong under `if TYPE_CHECKING:` when they would add a runtime
  import cycle.

## Runtime Validation with pydantic v2

```python
from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, field_validator

class User(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    id: int = Field(ge=1)
    email: str = Field(min_length=3, pattern=r".+@.+")

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        return value.lower()

user = User.model_validate({"id": 1, "email": "A@B.C"})
users = TypeAdapter(list[User]).validate_python([{"id": 1, "email": "a@b.c"}])
raw = user.model_dump_json()
```

- `TypeAdapter` validates arbitrary types (`list[User]`, `User | None`) without a wrapper
  model; it is the right tool for function boundaries.
- `model_validate(..., from_attributes=True)` reads ORM/attribute objects; configure
  `ConfigDict(from_attributes=True)` or pass per call.
- `field_validator(mode="before"|"after")` and `model_validator(mode="after")` cover field
  and cross-field rules; return `Self` from `model_validator(mode="after")`.
- `@computed_field`, `@field_serializer`, `@model_serializer` control output shape;
  `model_dump(exclude_unset=True)` is essential for PATCH semantics.
- `validate_call` enforces annotations on ordinary functions; use it at boundaries, not in
  hot loops.
- Setting `strict=True` disables coercion ("1" is not `int`); default lax mode is usually
  right for HTTP/JSON, strict for internal FFI.
- `ConfigDict(extra="forbid")` prevents silent payload drift; log the resulting
  `ValidationError.errors()` without echoing secrets.

**Anti-patterns**

- Pydantic v1 spellings: `parse_obj`, `.dict()`, `.json()`, inner `class Config`, `@validator`.
- Models with side effects in validators (DB calls, network) — validation must be pure.
- `Any` fields that defeat the point of the model; use discriminated unions
  (`Field(discriminator=...)`) for polymorphic payloads.
- Using a `BaseModel` where a frozen dataclass suffices in a hot path.

## Escape Hatches and Migration

- `cast(T, x)` only when a runtime invariant cannot be expressed; keep it at boundaries.
- `# type: ignore[code]` must carry the code and a short reason; enable
  `warn_unused_ignores`/`reportUnnecessaryTypeIgnoreComment` so stale ignores fail CI.
- Treat `Any` as an import from untyped libraries: wrap once in a typed adapter function,
  then keep the rest of the codebase `Any`-free.
- Migration: `typing.List/Dict/Optional` to builtins and `|`; module `TypeVar` to PEP 695;
  `TypeGuard` to `TypeIs` where both branches narrow; pydantic v1 to v2 via the official
  migration table; `Callable[..., X]` to `Callable[P, X]` when a decorator forwards args.

## Checklist

- [ ] Strict checker configuration committed and enforced in CI, with a ratcheting baseline
      if adopted late.
- [ ] Public API fully annotated; `Any` occurrences reviewed and localized.
- [ ] Protocols used for external/duck-typed dependencies; ABCs for owned hierarchies.
- [ ] Generics use PEP 695; defaults via PEP 696 where callers benefit.
- [ ] TypedDict + `Unpack` replace `**kwargs: Any`; `ReadOnly` protects shared payloads.
- [ ] Enum/union matches end in `assert_never`.
- [ ] `LiteralString` on query sinks; external input validated with pydantic v2 and
      `extra="forbid"`.
- [ ] Ignores/casts have codes and reasons; unused ignores fail the build.
