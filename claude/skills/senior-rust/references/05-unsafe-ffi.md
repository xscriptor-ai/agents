# Unsafe, Soundness, and FFI

Scope: when `unsafe` is justified, raw pointers and aliasing rules, `Pin`, building sound safe abstractions, Miri, C ABI and bindgen, pyo3/wasm-bindgen interop, and auditing unsafe code.

## The Soundness Contract

- `unsafe` does not disable the borrow checker; it grants five extra powers:
  1. Dereference raw pointers.
  2. Call `unsafe` functions (including foreign functions).
  3. Access fields of a `union`.
  4. Mutate a mutable `static` (edition 2024 requires `&raw mut` for references; verify upstream).
  5. Implement an `unsafe` trait (`unsafe impl Send/Sync`).
- Soundness means: **no safe code using this API can trigger undefined behavior**, for all inputs and all interleavings, including other threads.
- UB examples: data races, dangling/unaligned pointers, out-of-bounds reads/writes, aliasing violations (two `&mut` to the same memory), invalid values for a type, calling a function with the wrong ABI.
- Rules: keep `unsafe` blocks minimal, document each with a `// SAFETY:` comment stating the invariant, and expose a safe wrapper whose type system prevents misuse.
- Enable `unsafe_op_in_unsafe_fn` (warn by default, deny in edition 2024): every unsafe operation gets its own explicit `unsafe {}` block inside `unsafe fn`.
- `#[unsafe(no_mangle)]`/`#[unsafe(export_name = "...")]` in edition 2024 make the risky part explicit; older editions accept bare attributes with a lint.

```rust
/// # Safety
/// `ptr` must be valid for reads of `len` initialized bytes and aligned.
unsafe fn checksum(ptr: *const u8, len: usize) -> u32 {
    assert!(!ptr.is_null());
    let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
    bytes.iter().fold(0u32, |acc, &b| acc.wrapping_add(b as u32))
}
```

## Raw Pointers and Provenance

- `*const T`/`*mut T` carry provenance in the abstract machine (Stacked Borrows/Tree Borrows); casting through integers (`ptr as usize`) strips it and is only sound if provenance is restored correctly. Prefer `ptr::with_exposed_provenance`/`expose_provenance` (1.84+, verify upstream) over raw integer casts.
- Create with `&raw const x` / `&raw mut x` (stable since 1.82, verify upstream) or `std::ptr::addr_of!/addr_of_mut!` to avoid creating intermediate references.
- `NonNull<T>` is covariant, null-optimized, and documents non-null invariants; use it for internal pointers.
- `.as_ref()`/`.as_mut()` on pointers are `unsafe` and require validity; `&*ptr` needs alignment, non-null, dereferenceable, and initialized (unless the type permits uninit, e.g., `MaybeUninit`).
- Never derive references to uninitialized memory. Use `MaybeUninit<T>` and only `assume_init` after all fields are written.
- Prefer safe alternatives first: slices with `get`, `split_at`, `Vec::spare_capacity_mut`, `bytemuck`/`zerocopy` for casts, `bytemuck::Pod` for plain-old-data.

### Aliasing quick rules

| Reference | Rule |
|---|---|
| `&T` | no writes anywhere in the referent for its lifetime; many may coexist |
| `&mut T` | exclusive; no other `&`/`&mut` alias for its lifetime |
| `UnsafeCell<T>` | the only legal path to interior mutation; raw access must be synchronized |
| `&Cell<T>` | fine to mutate, but `T: Copy` and no reentrancy through the same `&Cell` |
| reborrow `&mut *p` | creates a fresh exclusive borrow; the old one is invalid until it ends |

Miri detects most violations. Aliasing rules are not a finalized spec; write code that satisfies both Stacked Borrows and Tree Borrows where possible.

## Pin and Self-Referential Types

- `Pin<P>` is a guarantee that the pointee will not move again, until it is dropped. `Unpin` types ignore the guarantee.
- `Pin<&mut T>`: safe `&mut T` access via `get_mut()` only if `T: Unpin`; otherwise `unsafe { get_unchecked_mut() }` with the structural-pinning invariant.
- Never move a `!Unpin` value after pinning. `std::pin::pin!` and `Box::pin` are safe constructors; `Pin::new` requires `T: Unpin`.
- Async blocks are `!Unpin` when they hold references across await; executors pin them in place.
- Structural pinning: if a wrapper exposes a field through `Pin<&mut Field>` and relies on field stability, it cannot implement `Drop` that moves the field, and unsafe projection code must uphold "never move" for that field. Use `pin-project-lite`/`pin-project` instead of hand-rolling projections.
- `PhantomPinned` makes a type `!Unpin`; it costs nothing.

```rust
use std::pin::{pin, Pin};
async fn demo() { let fut = pin!(some_async()); fut.await; }
```

## Building Sound Safe Abstractions

- Pattern: a private owned buffer (`Vec`, `Box<[MaybeUninit<T>]>`) plus a safe API that maintains initialization and aliasing invariants; unsafe is confined to a few methods.
- Encapsulate: `struct TinyVec<T> { buf: Vec<T>, len: usize }` internals are private; public methods take `&self`/`&mut self` and uphold invariants.
- Use `debug_assert!` for invariants that safe callers cannot violate but bugs might.
- Drop correctly: partially initialized values require dropping only initialized elements (`drop_in_place` on slices), and panics during drop need guards (`DropGuard`/`ManuallyDrop` patterns).
- `unsafe impl Send/Sync` needs a proof: describe which fields, which synchronization makes cross-thread access safe, and why no aliasing rule is broken. If the proof needs more than three sentences, redesign.
- Panics must not cross an unsafe abstraction boundary in a half-updated state; restore invariants before propagating panics.

## Miri

- `cargo +nightly miri test` interprets MIR and checks UB, leaks, data races, and invalid values. Most useful flags: `-Zmiri-strict-provenance`, `-Zmiri-symbolic-alignment-check`, `-Zmiri-many-seeds`, and Tree Borrows (`MIRIFLAGS=-Zmiri-tree-borrows`; verify defaults as they change).
- Limitations: no FFI (unless shims exist), only supported targets (host-like), much slower than native, and non-deterministic timing does not exist (races are modeled). Unsupported code produces "unsupported operation" errors rather than proof of soundness.
- Run Miri on the unsafe-heavy crate or module, not necessarily the whole workspace; use `#[cfg(miri)]` shims for syscalls and time.
- A clean Miri run is necessary but not sufficient: concurrency bugs under real schedulers still need loom (see `./08-testing.md`) and stress tests.
- CI: nightly toolchain plus `rustup component add miri`, `cargo miri setup`, cache the sysroot.

## C ABI and bindgen

- `extern "C"` is the stable interchange ABI. Use `repr(C)` for structs crossing the boundary and `repr(transparent)` for newtypes. Rust's default `repr(Rust)` layout is unspecified.
- Edition 2024: `extern` blocks require `unsafe extern "C" { ... }`; choose `"C-unwind"` when panics or exceptions may propagate across the boundary and that behavior is intended.
- Generation: `bindgen` (C headers to Rust) in a `build.rs`; `cbindgen` (Rust to C headers); keep generated files checked in or cached for reproducible builds.
- Ownership rules must be explicit in the header docs: who allocates, who frees, which allocator. Freeing a Rust allocation with `free(3)` (or vice versa) is UB with different allocators.
- Strings: `CStr::from_ptr` is unsafe and requires NUL-termination; `CString::new` rejects interior NUL. Use `std::ffi::{c_char, c_int}` rather than `libc` types where possible.
- Callbacks: never let unwinding cross `extern "C"` (abort on panic or catch and translate); document threading expectations; pass an opaque `void*` context back to Rust.
- Optional/error conventions: return status codes, use out-parameters for values, and translate errors into a stable C error enum. Never return Rust references that Rust may free later.
- Structs returned by value must be `#[repr(C)]` and contain only C-compatible fields; avoid `bool` (use `u8`) and Rust enums (use `c_uint` constants).
- Cargo: `[lib] crate-type = ["cdylib", "staticlib"]`; `panic = "abort"` in the FFI profile if unwinding cannot be contained.

```rust
#[repr(C)]
pub struct Span { pub ptr: *const u8, pub len: usize }

#[unsafe(no_mangle)]
pub extern "C" fn span_free(s: Span) {
    if !s.ptr.is_null() {
        // SAFETY: ptr/len came from Box<[u8]> with the same allocator in this library.
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(s.ptr as *mut u8, s.len)) });
    }
}
```

## Python and WebAssembly Interop

- pyo3 (0.2x line, verify upstream):
  - Prefer the `Bound<'py, T>` API; `#[pyfunction]`/`#[pymodule]`; `Python::attach`/`with_gil` has evolved — verify current naming upstream.
  - The GIL protects Python objects but not Rust data; do not block holding the GIL, release it for long Rust work (`py.allow_threads` or equivalent).
  - Map `Result<T, E>` to `PyErr` with `From<E> for PyErr`; keep error translation at the boundary.
  - Build with `maturin`; use `abi3` wheels for forward compatibility with a version floor; profile release with `lto = "thin"`.
  - Panics in `#[pyfunction]` are converted to Python exceptions by the runtime, but prefer returning `Result`.
- wasm-bindgen:
  - `#[wasm_bindgen]` for exported functions/structs; `JsValue` for JS interop, `web_sys`/`js_sys` bindings.
  - Wasm linear memory is not shared: JS strings are copied; use typed arrays (`Uint8Array`) for bulk data to avoid conversion overhead.
  - `wasm32-unknown-unknown` + `wasm-bindgen-cli` (version must match the crate; verify) or `wasm-pack` for bundling.
  - Panics abort the wasm instance by default; use `console_error_panic_hook` in dev for stack traces.
  - Test in Node/browsers with `wasm-bindgen-test`; keep JS glue generated, not hand-edited.

## Auditing Unsafe Code

- Inventory: `rg "unsafe"`, `cargo geiger` for dependencies; track unsafe surface per crate and require review for increases.
- Documentation: each public `unsafe fn` must have a `# Safety` doc section; every unsafe block a `// SAFETY:` comment referencing the invariant it upholds.
- Encapsulation audit: verify every public safe function keeps invariants (check constructor paths, `Default`, `Clone`, `Deserialize` derived impls — derive can smuggle invalid states past constructors).
- Fuzzing: `cargo-fuzz` targets for parsers and unsafe-heavy code paths; run under sanitizers (ASan/TSan) where Miri cannot (FFI).
- Sanitizers: `-Zsanitizer=address` / `thread` on nightly for FFI and cross-thread code; not a substitute for Miri's aliasing checks.
- Keep unsafe code in a dedicated module or crate with tests that exercise edge cases, alignment, zero-length slices, and null handling.
- Dependencies: `cargo-deny`/`cargo-audit` in CI; prefer well-maintained crates with documented safety posture for crypto and parsing.

## Anti-Patterns

- `unsafe` to defeat the borrow checker for convenience.
- "I tested it once" as a soundness argument; no Miri, no fuzzing, no review.
- Returning raw pointers to stack data or references derived from temporaries.
- `mem::transmute` for type punning; prefer `bytemuck`, `zerocopy`, or explicit conversion.
- `unsafe impl Send/Sync` on a type containing `Rc`, `RefCell`, raw pointers, or interior mutability without synchronization.
- Freeing memory across allocator or language boundaries.
- Letting panics unwind across FFI boundaries.
- Multiple `&mut` derived from the same `UnsafeCell` without synchronization.
- Ignoring `MaybeUninit` initialization before `assume_init`.

## Checklist

- [ ] Every `unsafe` block has a `// SAFETY:` comment and a test that would fail on violation.
- [ ] `unsafe` is minimized and wrapped in a safe API whose misuse cannot compile.
- [ ] Miri passes for unsafe modules; tree-borrows mode checked.
- [ ] FFI types are `#[repr(C)]`/`#[repr(transparent)]`, ABI (including unwind) is explicit.
- [ ] Ownership and allocator rules documented for both sides of FFI.
- [ ] `unsafe impl Send/Sync` has a written proof and required synchronization.
- [ ] Pinned types never move after pinning; projections use a vetted crate.
- [ ] CI tracks unsafe surface (`cargo geiger`) and denies increases without review.
