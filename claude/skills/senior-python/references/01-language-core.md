# Language Core (Python 3.12-3.14)

Syntax and semantics of modern CPython: PEP 695, pattern matching, exception groups, f-strings and t-strings, dataclass tooling, free-threading, and removals.

## Version Map

| Version | Headline features | Status (2026) |
|---|---|---|
| 3.12 | PEP 695 generics, PEP 701 f-strings, `itertools.batched`, `override`, per-interpreter GIL C-API, `distutils`/`imp` removed | Supported, practical floor for new code |
| 3.13 | Free-threaded build (PEP 703), experimental JIT (PEP 744), `TypeIs`/`ReadOnly`/TypeVar defaults, `warnings.deprecated`, PEP 594 dead batteries removed | Supported, default choice |
| 3.14 | Deferred annotations (PEP 649/749), t-strings (PEP 750), free-threading officially supported (PEP 779), `except` without parens (PEP 758), `compression.zstd`, `concurrent.interpreters` | Supported, verify library wheel coverage |

Version floors are deliberate: do not backport these idioms to 3.10/3.11 projects.

## PEP 695 Generics

```python
from collections.abc import Iterable

def first[T](items: Iterable[T], default: T | None = None) -> T | None:
    return next(iter(items), default)

class Box[T]:
    def __init__(self, value: T) -> None:
        self._value = value

    @property
    def value(self) -> T:
        return self._value

type Pair[T] = tuple[T, T]
type Matrix[T] = list[list[T]]
```

- Scoped type parameters replace module-level `TypeVar("T")`; covariance is inferred from use.
- Bounds and constraints: `def f[T: int | str](x: T)`, `class Repo[T: BaseModel]`.
- Variadic generics: `class Array[*Shape]`, `tuple[*Ts]`, `Unpack[Ts]`.
- `type` aliases are lazy and introspectable: `Pair.__value__`, `Pair.__type_params__`.
- Runtime access: `Box.__type_params__`; use `typing.get_type_hints` or `annotationlib` for annotations.
- [Typing depth](./02-typing.md) covers variance, `ParamSpec`, and defaults.

**Anti-patterns**

- Keeping module-level `TypeVar`s that "belong" to one generic function or class.
- `type X = Any` aliases that erase checker signal; prefer a `Protocol`.
- Using `__value__` at runtime for validation; use pydantic `TypeAdapter` instead.

## Pattern Matching

```python
from dataclasses import dataclass

@dataclass
class Point:
    x: float
    y: float

def classify(msg: dict) -> str:
    match msg:
        case {"type": "ping", "seq": int(seq)} if seq >= 0:
            return f"ping {seq}"
        case {"type": "move", "to": Point(x=0, y=y)}:
            return f"axis {y}"
        case [Point(x=x1), Point(x=x2)] if x1 < x2:
            return "ordered pair"
        case _:
            return "unknown"
```

- Patterns support literals, captures, `|` alternatives, mappings, sequences, class patterns, guards.
- Mapping patterns are partial: keys not listed are ignored; `**_` captures the rest.
- Sequence patterns bind by position; starred names capture remainders (`[first, *rest]`).
- Class patterns use `__match_args__`, which dataclasses generate automatically.
- `case str() | bytes()` is valid; `case int | str` without call syntax is not a type pattern.
- Use `assert_never` on the fallthrough for closed unions instead of a bare `_` branch
  (see [typing](./02-typing.md)).

**Anti-patterns**

- Using `match` as a `switch` over unrelated side-effect branches; `if/elif` is clearer.
- Omitting a total `case _` for open input; an unmatched value silently does nothing.
- Capturing with a bare name when you meant a constant: `case status:` matches anything.

## Exception Groups and `except*`

```python
import asyncio

async def fetch(url: str) -> str:
    await asyncio.sleep(0.01)
    if "bad" in url:
        raise ValueError(f"invalid: {url}")
    return url

async def main() -> None:
    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(fetch("https://ok"))
            tg.create_task(fetch("https://bad"))
    except* ValueError as eg:
        print("value errors:", [str(e) for e in eg.exceptions])
    except* TimeoutError:
        print("timeouts")
```

- `ExceptionGroup`/`BaseExceptionGroup` (3.11) carry multiple exceptions; `except*` runs once
  per matching subgroup and re-raises the remainder.
- `TaskGroup` raises an `ExceptionGroup`; unwrap deliberately, never `except Exception` around it.
- `eg.subgroup(ValueError)` / `eg.split()` for programmatic handling.
- `except*` cannot be mixed with bare `except` in the same `try`.
- 3.14 allows `except ValueError, TypeError:` without parentheses (PEP 758); keep parentheses
  for 3.12/3.13 compatibility.

**Anti-patterns**

- `except Exception: pass` around a `TaskGroup`, which hides sibling failures.
- Logging `eg` without traversing `eg.exceptions`, losing root causes.

## f-strings and t-strings

PEP 701 (3.12) makes f-strings full expressions: nested same-type quotes, backslashes,
comments, and multi-line expressions are legal.

```python
user = {"name": "ada", "id": 7}
print(f"{user["name"]!r:>10}")          # nested double quotes
print(f"{', '.join(map(str, [1, 2]))}") # calls and comprehensions
```

3.14 adds template strings (PEP 750) for libraries that must process values safely:

```python
from string.templatelib import Interpolation, Template

def render(t: Template) -> str:
    out: list[str] = []
    for part in t:
        out.append(part if isinstance(part, str) else html_escape(str(part.value)))
    return "".join(out)

t = t"<p>{user['name']}</p>"  # Template, not str
```

- Use t-strings for SQL/HTML/query builders; the library decides escaping instead of the
  interpreter.
- Never `str(template)` and inject it into markup without escaping.
- f-string format spec still applies: `f"{value:.2f}"`, `!r`, `!s`, `!a`.

## Deferred Annotations (3.14)

PEP 649/749 evaluate annotations lazily on first `__annotations__` access, so forward
references work without `from __future__ import annotations` and runtime introspection is
cheaper on import.

```python
class Node:
    def __init__(self, child: Node | None = None) -> None:
        self.child = child

from annotationlib import Format, get_annotations
get_annotations(Node.__init__, format=Format.FORWARDREF)
```

- `from __future__ import annotations` remains valid; on 3.14 it implies stringized
  annotations and changes `annotationlib` results. Libraries must use `annotationlib` or
  `typing.get_type_hints`, not raw `__annotations__`.
- FastAPI, pydantic, and dataclasses have adapted; pin minimum versions that understand
  `annotationlib` (verify upstream release notes).
- If a library reads `__annotations__` directly, test it on 3.14 before upgrading.

## Dataclasses vs attrs vs Pydantic

| Tool | Best for | Validation | Slots | Perf notes |
|---|---|---|---|---|
| `dataclasses` (stdlib) | Internal records, config objects | None built in (`__post_init__`) | `slots=True` (3.10+) | Fast instantiation; no conversion |
| `attrs` | Records needing validators/converters | `attrs.validators` | Default since `@define` | Mature, very fast; `attrs.resolve_types` |
| `pydantic.dataclasses` | Validated dataclass-style models | Full pydantic v2 | `slots=True` supported | Slower than plain dataclasses; JSON via `TypeAdapter` |
| `pydantic.BaseModel` | API/IO boundaries, settings | Full pydantic v2 | Internal | Ideal at edges, avoid in hot loops |

```python
from dataclasses import dataclass, field

@dataclass(frozen=True, slots=True, kw_only=True)
class RetryPolicy:
    attempts: int = 3
    backoff: float = 0.5
    tags: tuple[str, ...] = field(default_factory=tuple)
```

- Mutable defaults require `field(default_factory=...)`; `slots=True` blocks accidental
  attribute growth and reduces memory.
- `frozen=True` gives `__hash__` only if all fields are hashable; equality semantics change.
- Use `@dataclass_transform` when writing decorators/frameworks that should look like
  dataclasses to type checkers (3.11+, or `typing_extensions`).

**Anti-patterns**

- `@dataclass` with a mutable default (`items: list = []`) — `ValueError` at class definition.
- Reaching for pydantic models for internal hot-path objects; validation dominates cost.
- Mixing attrs and dataclasses in one layer without a reason.

## Free-Threaded Interpreter and JIT

| Build | Flag | State | Guidance |
|---|---|---|---|
| Default CPython | GIL on | Supported | Default for production |
| Free-threaded | `python3.13t`, `--disable-gil` | 3.13 experimental, 3.14 officially supported (PEP 779) | Benchmark end-to-end; C extensions must declare thread-safety |
| JIT | `--enable-experimental-jit` | Experimental since 3.13 | Do not enable for production; benchmark before believing gains |

- Detect at runtime: `sysconfig.get_config_var("Py_GIL_DISABLED")`,
  `sys._is_gil_enabled()`, `PYTHON_GIL=0`/`-X gil=0` to disable at start on `t` builds.
- Single-thread throughput on free-threaded builds is typically lower than GIL builds;
  parallelism only pays for CPU-bound, multi-threaded workloads.
- C extensions are the blocker: a single unmarked extension can force the GIL or crash.
  Audit wheels with `py-free-threading`-style compatibility trackers (verify upstream).
- Per-interpreter GIL (PEP 684) is orthogonal; 3.14 adds `concurrent.interpreters` and
  `InterpreterPoolExecutor` for isolated sub-interpreters.
- Prefer processes today unless profiling on free-threaded shows a clear win.

## Removals, Deprecations, and Wall-Clock Items

| Item | Change | Action |
|---|---|---|
| `distutils` | Removed 3.12 | Use `setuptools`/`hatchling`; migrate `setup.py` |
| `imp` | Removed 3.12 | Use `importlib` |
| Dead batteries: `cgi`, `telnetlib`, `crypt`, `pipes`, `sndhdr`, `spwd`, `uu`, `xdrlib`, `mailcap`, `nntplib`, `ossaudiodev`, `sunau`, `aifc`, `audioop`, `chunk`, `imghdr`, `msilib`, `nis` | Removed 3.13 (PEP 594) | Equivalent PyPI packages |
| `lib2to3`/`2to3` | Removed 3.13 | `ruff` with `UP` rules |
| `datetime.utcnow()`, `utcfromtimestamp()` | Deprecated 3.12 | `datetime.now(timezone.utc)` |
| `asyncio.get_event_loop()` implicit creation | Deprecated; tightened in 3.14 (verify upstream) | `asyncio.run`, `asyncio.Runner`, `get_running_loop` |
| `multiprocessing` `fork` default | Deprecated pattern; Linux default moving toward `forkserver` in 3.14 (verify upstream) | Use `spawn`/`forkserver` explicitly |
| `return`/`break`/`continue` exiting `finally` | SyntaxWarning in 3.14 (PEP 765) | Restructure control flow |
| `tarfile` extraction | `filter="data"` default in 3.14 | Keep explicit `filter=` on older versions |

## Small Stdlib Wins

```python
import itertools, tomllib, graphlib

list(itertools.batched(range(5), 2))            # [(0,1),(2,3),(4,)]
with open("pyproject.toml", "rb") as fh:
    cfg = tomllib.load(fh)
graphlib.TopologicalSorter({"a": {"b"}}).static_order()
```

- `functools.cache` for unbounded memoization, `lru_cache(maxsize=None)` equivalent.
- `zoneinfo.ZoneInfo("UTC")` instead of `pytz`; `datetime` is aware-only in new code.
- `hashlib.file_digest`, `secrets.token_urlsafe`, `itertools.pairwise`.
- 3.14: `compression.zstd` (PEP 784) for zstd without third-party wheels.
- `pathlib.Path.walk` avoids `os.walk` string paths.

## Migration Notes

- Replace `Optional[X]`, `List[X]`, `Dict[K, V]` with `X | None`, `list[X]`, `dict[K, V]`.
- Replace module `TypeVar` + `Generic[T]` with PEP 695 syntax on 3.12+; keep old style only
  if supporting 3.11 or below ([typing](./02-typing.md)).
- Replace `datetime.utcnow()` with aware UTC everywhere; write a test that fails on naive
  timestamps.
- Run `ruff check --select UP` before touching semantics; it automates most 3.12+ idioms.
- On 3.14 upgrades, audit annotation-consuming libraries (DI, ORM, serialization) first.

## Anti-Patterns

- Catching broad `Exception` in library code without re-raising or wrapping with context.
- Mutable default arguments (`def f(x, acc=[])`) and mutable class attributes.
- `eval`/`exec` on any input that crosses a trust boundary.
- Using `match` with side effects in patterns or guards.
- `assert` for input validation: stripped under `-O`.
- Ignoring `ResourceWarning`/`DeprecationWarning` in CI; both precede removals.

## Checklist

- [ ] `requires-python` declared and CI covers oldest + newest supported minors.
- [ ] No use of removed stdlib modules or deprecated `datetime.utcnow()`.
- [ ] Generics use PEP 695 where the floor allows; no orphan `TypeVar`s.
- [ ] Exception groups handled via `except*` or explicit subgroup extraction.
- [ ] Annotation-consuming libraries validated on the target interpreter.
- [ ] Dataclass policy documented (stdlib/attrs/pydantic) and applied consistently.
- [ ] Free-threaded/JIT decisions backed by a benchmark, not enabled by default.
