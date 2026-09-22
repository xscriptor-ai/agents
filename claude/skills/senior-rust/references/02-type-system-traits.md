# Type System and Traits

Scope: traits, associated types, generics versus `dyn`, blanket impls, marker traits, newtypes, conversions, operator traits, and `std::error::Error` integration.

## Trait Design Fundamentals

- A trait is a contract plus optional default methods. Keep required methods minimal; implement defaults in terms of them.
- Supertraits (`trait Conn: Send + Sync`) express requirements, not inheritance. Prefer composing small traits over deep supertrait chains.
- Methods taking `&self` vs `&mut self` vs `self` define the object-safety and usability surface. Returning `Self` or generic methods makes a trait non-object-safe.
- Coherence: a downstream crate cannot implement a foreign trait for a foreign type. Design extension points with local traits or newtypes when downstream impls are expected.

```rust
pub trait Store {
    type Error;
    fn get(&self, key: &str) -> Result<Option<Vec<u8>>, Self::Error>;
    fn put(&mut self, key: &str, value: &[u8]) -> Result<(), Self::Error>;
    fn contains(&self, key: &str) -> Result<bool, Self::Error> {
        Ok(self.get(key)?.is_some()) // default method
    }
}
```

## Associated Types vs Generic Parameters

| Question | Associated type (`trait Trait { type Out; }`) | Generic parameter (`trait Trait<T>`) |
|---|---|---|
| One impl per type? | yes, by construction | multiple impls possible |
| Caller names the type? | no; inferred from impl | yes, turbofish |
| Object safety | usually keeps `dyn` possible | rarely dyn-compatible |
| Typical use | `Iterator::Item`, `Store::Error` | `From<T>`, `PartialEq<Rhs>` |
| Ergonomics | no type annotation at call sites | annotation/noise at call sites |

Rule: if the trait conceptually has exactly one output per implementor, use an associated type. If a type may implement the trait for several parameter types (`Add<Meters>` and `Add<Feet>`), use generics.

## Generics vs `dyn` (Static vs Dynamic Dispatch)

| Criterion | Generics (`impl Trait`/`<T: Trait>`) | `dyn Trait` |
|---|---|---|
| Dispatch | static, inlinable | vtable, indirect |
| Binary size | monomorphized per type | one copy |
| Heterogeneous collections | no | yes (`Vec<Box<dyn Trait>>`) |
| Compile time | worse as combinations grow | better |
| Object safety required | no | yes |
| Plugin/runtime selection | no | yes |

- Prefer generics in hot paths and library APIs; prefer `dyn` at process boundaries (plugins, heterogeneous lists, avoiding combinatorial explosion).
- `impl Trait` in argument position is sugar for a generic parameter; in return position it hides a concrete (possibly unnameable) type.
- RPITIT (`-> impl Trait` in trait methods) is stable on modern Rust (1.75+, verify upstream). It makes traits non-object-safe unless `dyn` support is designed.
- Boxed trait objects allocate: `Box<dyn Error + Send + Sync>` costs one allocation. Accept it at boundaries, avoid in tight loops.

```rust
fn total<I: Iterator<Item = u64>>(it: I) -> u64 { it.sum() }          // static
fn total_boxed(it: Box<dyn Iterator<Item = u64>>) -> u64 { it.sum() } // dynamic
```

### Object safety quick check

A trait can be used as `dyn Trait` if it has no generic methods, no `Self`-returning methods (except `where Self: Sized`), no associated constants, and `Self: Sized` is not required. Add `where Self: Sized` on non-object-safe methods to keep the rest dyn-compatible.

## Blanket Impls and Coherence

- Blanket impl: `impl<T: Display> Loggable for T`. Powerful, but any downstream type automatically gets it and overlap becomes likely.
- The orphan rule allows `impl LocalTrait for ForeignType` and `impl ForeignTrait for LocalType`.
- Overlap checks are conservative; two blanket impls that "obviously" do not overlap still conflict. Use newtypes or sealed traits to disambiguate.
- Common std blanket impls to know: `From<T> for T`, `From<T> for Option<T>`, `Into<T> for T`, `Borrow<T> for T`, `AsRef<T> for T`, `Any` for `'static` types.

```rust
pub trait Encode { fn encode(&self, out: &mut Vec<u8>); }
impl<T: serde::Serialize> Encode for T { /* blanket */ }
// Now a manual impl for a local type would conflict; use a newtype instead.
```

## Marker Traits and Auto Traits

| Trait | Meaning | Opt-out |
|---|---|---|
| `Send` | can move across threads | `PhantomData<*const ()>` or `Rc` field |
| `Sync` | can be shared by reference across threads | `Cell`/`RefCell` field |
| `Unpin` | safe to move after pinning | `PhantomPinned` |
| `Sized` | known size at compile time | `?Sized` bound |
| `Copy` | bitwise duplicate, no drop | manual `Clone` |
| `UnwindSafe` | safe to observe after panic | `AssertUnwindSafe` wrapper |

- `Send`/`Sync` are auto traits: composed structurally from fields. `unsafe impl Send for MyType {}` is an invariant you now own; document why.
- Negative impls (`impl !Send`) remain unstable for user types; use marker fields to remove auto traits.
- `PhantomData<T>` communicates ownership, variance, and auto-trait behavior for types with no field of that type.

## Newtypes and Type-State

- Newtype: `struct UserId(u64);` avoids primitive obsession, enables trait impls on foreign types, and centralizes validation.
- Add `#[repr(transparent)]` when the wrapper must have the same ABI as the inner type (FFI).
- Implement `From<Inner>` only when the conversion is infallible and identity-preserving; use a `try_new` constructor for validation.
- Type-state: encode lifecycle in a type parameter (`Request<Draft>`, `Request<Sent>`) so invalid transitions fail to compile. Cost: more generics and sometimes harder `dyn` integration.

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Email(String);

impl Email {
    pub fn parse(raw: &str) -> Result<Self, EmailError> {
        let raw = raw.trim();
        if raw.contains('@') && !raw.contains(char::is_whitespace) {
            Ok(Self(raw.to_ascii_lowercase()))
        } else {
            Err(EmailError::Invalid)
        }
    }
}
impl std::fmt::Display for Email { fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result { f.write_str(&self.0) } }
```

### `Deref` anti-pattern

Do not implement `Deref` to gain method forwarding on non-pointer types. It leaks the inner API, confuses inference, and breaks `dyn` bounds. Use explicit methods or `AsRef`. `Deref` is for smart pointers and wrapper types whose entire purpose is delegation.

## Conversions

| Trait | Direction | Failure | Convention |
|---|---|---|---|
| `From<T>` | infallible | no | also gives `Into` |
| `TryFrom<T>` | fallible | `Error` assoc type | also gives `TryInto` |
| `AsRef<T>` | borrowed view | no | cheap, non-consuming |
| `Borrow<T>` | borrowed view with semantic equality | no | map keys/lookups |
| `FromStr` | parse from `&str` | `Err` | `"x".parse::<T>()` |
| `Serialize`/`Deserialize` | data mapping | varies | serde |

- Implement `From`, get `Into` free. Never implement both.
- Use `AsRef<Path>` for path-like parameters and `impl Into<String>` for owned string parameters at API boundaries.
- `Borrow` differs from `AsRef`: `String: Borrow<str>` promises `Hash`/`Eq` agree with `str`, which is what makes `HashMap<String, _>::get("key")` work.
- Keep conversions lossless. If a conversion truncates (`u64 -> u32`), make it `TryFrom` or name it `truncate_to_u32`.

```rust
impl From<io::Error> for AppError { fn from(e: io::Error) -> Self { Self::Io(e) } }
impl TryFrom<&str> for Port { type Error = PortError; fn try_from(s: &str) -> Result<Self, _> { /* ... */ } }
```

## Operator Traits and Core Contracts

| Trait | Operator | Notes |
|---|---|---|
| `Add`, `Sub`, `Mul`, `Div` | `+ - * /` | take `self`/`&self`; define `AddAssign` for mutation |
| `Neg`, `Not` | `- !` | `Not` on booleans is logical |
| `Index`, `IndexMut` | `[]` | may panic; document bounds behavior |
| `PartialEq`/`Eq` | `== !=` | `Eq` requires reflexivity; floats are only `PartialEq` |
| `PartialOrd`/`Ord` | `< <= > >=` | implement `Ord` with a total, consistent order |
| `Hash` | hashing | must agree with `Eq`; derive both together |
| `Display`/`Debug` | `{}`/`{:?}` | `Display` is user-facing, `Debug` is diagnostics |
| `Deref` | `*` | see anti-pattern above |
| `Drop` | scope exit | cannot be called directly; use `mem::drop` |

- Derive `Debug` on every public type; include it in `deny(missing_debug_implementations)` policies.
- Manual `PartialEq` without `Hash` consistency silently breaks `HashMap`.
- For newtypes used as keys, derive `PartialEq, Eq, Hash` or implement all three with the same field set.

## Error Trait Integration

- A custom error type should implement `std::error::Error` (via `thiserror` or manually), `Display`, and `Debug`.
- `Error::source()` exposes the causal chain; `anyhow` and tracing walk it. Provide `source` via `#[from]`/`#[source]` attributes.
- `Box<dyn std::error::Error + Send + Sync + 'static>` is the universal erased error; use it at API boundaries, not internally.
- Never implement `Error` for a type whose `Display` is empty or whose message duplicates the source without context.

```rust
#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("key not found: {key}")]
    NotFound { key: String },
    #[error("backend unavailable")]
    Backend(#[from] tokio::io::Error),
}
```

See `./04-error-handling.md` for the full policy on `thiserror` vs `anyhow` and boundary conversion.

## Advanced Patterns

- Sealed traits: `pub trait Foo: private::Sealed` prevents downstream impls while keeping the API public. Use for extension points you intend to grow.
- Extension traits: define a local trait with methods for a foreign type to add behavior (`trait VecExt { ... } impl<T> VecExt for Vec<T>`).
- GATs (generic associated types, `type Item<'a>`) are stable on modern Rust; use for lending iterators and view types. They add complexity — verify need first.
- `#[non_exhaustive]` on public structs/enums reserves the right to add fields/variants.
- Hygiene of derive: `#[derive(Clone)]` requires all fields `Clone`; a `derive` failure names the field, so fix the field rather than writing a manual impl that panics.

## Anti-Patterns

- Trait-per-type instead of functions/structs (`UserServiceTrait` for a single impl, never mocked): only introduce traits at seams you substitute or mock.
- `Deref` for code reuse.
- Generic explosion: 4+ type parameters on public types instead of boxing or enum dispatch.
- `impl Trait` in return position hiding a type callers must name for traits (e.g., returning `impl Iterator` when callers need `ExactSizeIterator`).
- Blanket impls over foreign traits that create coherence conflicts downstream.
- `Clone` derived on handle/resource types that should be moved, not duplicated.
- `anyhow::Error` in a public library API (see `./04-error-handling.md`).

## Checklist

- [ ] Traits exist at real seams; no speculative abstraction.
- [ ] Associated types used for one-output contracts; generics for multi-impl contracts.
- [ ] `dyn` used only where heterogeneity or runtime selection is required.
- [ ] Newtypes validate in constructors; no public field that breaks invariants.
- [ ] `From`/`TryFrom` used instead of ad-hoc `to_*` conversion methods.
- [ ] Error types implement `Error`, `Display`, `Debug` with a useful `source` chain.
- [ ] Every `unsafe impl Send/Sync` has a written justification.
- [ ] Derived `PartialEq`/`Hash`/`Ord` are mutually consistent.
