# Language Core: Ownership, Borrowing, Lifetimes, Data Modeling

Scope: the ownership/borrowing/lifetime mental model, smart pointers, enums, pattern matching, closures, iterators, and concrete fixes for borrow-checker fights.

## Ownership Mental Model

- Every value has exactly one owner. When the owner goes out of scope, the value is dropped.
- Assignment, passing by value, and returning move the value unless the type is `Copy`.
- `Copy` is a property of the type (no heap, no destructor semantics enforced); `Clone` is an explicit deep or shallow copy.
- Drop order: locals drop in reverse declaration order; struct fields drop in declaration order; tuple elements drop in order. Temporaries drop at the end of the enclosing statement.
- Edition 2024 changed the scope of temporaries in tail expressions and `if let`; code that relies on temporary drop timing should be tested on both editions. Verify upstream for exact rules.
- Use `std::mem::drop(x)` to end a borrow early; use `std::mem::take`/`replace` to move a value out through `&mut`.

```rust
struct Conn { name: String }
impl Drop for Conn { fn drop(&mut self) { /* close */ } }

fn take_ownership(c: Conn) -> String { c.name } // c dropped at end of fn
fn borrow(c: &Conn) -> &str { &c.name }          // no move, no drop
```

### Copy vs Clone decision table

| Situation | Use |
|---|---|
| Small scalar/identifier (`u64`, `f64`, `[u8; 16]`, enums of scalars) | derive `Copy` |
| Owns heap or resource (`String`, `Vec`, file handle) | `Clone` only, explicit |
| Type will be serialized/shared and is cheap | derive both |
| Contains `Drop` behavior | never `Copy` |

## Borrowing Rules

- At any time: any number of shared borrows (`&T`) OR exactly one mutable borrow (`&mut T`) — never both.
- Borrow ends at its last use under non-lexical lifetimes (NLL). Holding a `&mut` through an unrelated call still conflicts.
- Reborrowing (`&mut *x`) is implicit when passing `&mut` to functions; the original can be reused after the call returns.
- Returning a reference from a function requires the lifetime to come from an input (see elision below).
- Interior mutability (`Cell`, `RefCell`, `Mutex`, atomics) is the escape hatch when aliasing plus mutation is genuinely required.

### Lifetime elision rules

1. Each elided input lifetime becomes a distinct parameter lifetime.
2. If there is exactly one input lifetime, it is assigned to all elided outputs.
3. If there is `&self` or `&mut self`, its lifetime is assigned to all elided outputs.

```rust
fn first_word(s: &str) -> &str { /* ties output to s */ }
fn get<'a>(&'a self) -> &'a str { &self.name }
```

- `'static` as a bound means "may live for the whole program", not "must". `&'static str` is a reference to static storage; `T: 'static` on a generic means "contains no non-static borrows", which includes owned types like `String`.
- Structs holding borrows need explicit lifetimes: `struct Parser<'a> { src: &'a str }`. If that becomes viral, own the data (`String`, `Arc<str>`) at API boundaries.
- Lifetime elision does not apply inside closures or across `async` blocks; keep borrows short before `.await`.
- Higher-ranked trait bounds (`for<'a> Fn(&'a str)`) are occasionally needed; prefer `Fn(&str) -> ...` sugar.

## Smart Pointers

| Type | Sharing | Mutation | Thread-safe | Use when |
|---|---|---|---|---|
| `Box<T>` | single | via `&mut` | if `T: Send` | heap indirection, recursive types, trait objects |
| `Rc<T>` | shared | no (or with `RefCell`) | no | single-thread shared ownership, cheap clones |
| `Arc<T>` | shared | no (or with `Mutex`) | yes (atomics) | cross-thread shared ownership |
| `Weak<T>` | shared | no | matches parent | break reference cycles, caches, parent pointers |
| `Cell<T>` | single | copy-in/copy-out | no | small `Copy` state behind `&self` |
| `RefCell<T>` | single | runtime-checked | no | complex mutation behind `&self` |
| `Mutex<T>`/`RwLock<T>` | shared | lock | yes | shared mutable state across threads |
| `OnceLock<T>` | shared | set once | yes | lazily initialized global/config; `LazyLock` for init expressions (Rust 1.80+, verify upstream) |
| `Cow<'a, T>` | clone-on-write | via `to_mut` | varies | accept borrowed or owned, avoid allocations |

- `RefCell` panics on conflicting borrows at runtime. Use `try_borrow`/`try_borrow_mut` where a panic is unacceptable, and keep borrows short.
- `Mutex` poisoning: `.lock()` returns `Result`; `unwrap()` is defensible only when a panic while holding the lock already means the process should die. Otherwise recover or use `parking_lot::Mutex` (no poisoning).
- Never hold a `std::sync::MutexGuard` across `.await`. Use `tokio::sync::Mutex` only if the critical section must await; prefer restructuring to avoid async locks entirely. See `./03-async-concurrency.md`.
- `Rc` cycles leak. Store `Weak` for back/observer links and upgrade with `.upgrade()`.
- Prefer `Arc<str>`/`Arc<[T]>` over `Arc<String>`/`Arc<Vec<T>>` for immutable shared data (one indirection, immutable).
- Atomics (`AtomicUsize`, `AtomicBool`, `AtomicPtr`) belong in the standard library; use `Ordering::Relaxed` only for counters where no synchronization is implied. Verify the necessary ordering against the C++ memory model.

### Interior mutability hierarchy

```text
&mut T for free, else
  AtomicBool/AtomicUsize  (Copy, lock-free, cross-thread)
  Cell<T: Copy>           (no borrow checking, single thread)
  RefCell<T>              (runtime borrow checking, single thread)
  Mutex<T>/RwLock<T>      (blocking, cross-thread)
  tokio::sync::Mutex      (async-aware, cross-thread)
  channels                (ownership transfer instead of sharing)
```

Rule of thumb: if you reach for `Rc<RefCell<...>>` frequently, redesign around message passing or explicit state structs.

## Enums and Pattern Matching

- Prefer enums over boolean flags and over "nullable fields"; model the domain so invalid states do not compile.
- `match` must be exhaustive. Use `#[non_exhaustive]` on public enums so downstream matches can add a wildcard.
- `let ... else` for early exit without deep nesting.
- `matches!(x, Pat if guard)` for boolean tests.
- `if let` chains (`if let Some(x) = a && let Some(y) = b`) stabilize with edition 2024; verify upstream before relying on them in older editions.

```rust
#[derive(Debug)]
enum Job { Queued, Running { pid: u32 }, Done(ExitStatus), Failed(String) }

fn label(job: &Job) -> &'static str {
    match job {
        Job::Queued => "queued",
        Job::Running { .. } => "running",
        Job::Done(_) => "done",
        Job::Failed(_) => "failed",
    }
}

let Some(cfg) = load_config() else { return Err(Error::NoConfig) };
```

### Option/Result combinator quick table

| Need | Use |
|---|---|
| default | `unwrap_or`, `unwrap_or_else`, `unwrap_or_default` |
| convert to `Result` | `ok_or`, `ok_or_else` |
| chain fallible | `and_then`, `Result::and_then` |
| branch on both | `match`, `map_or`, `map_or_else` |
| swap `Result<Option<_>>` | `.transpose()` |
| replace with owned | `take()` |
| merge `Option<Result<_>>` | `and_then(|r| r.ok())` |

## Closures

- Closure traits: `Fn` (callable via `&`), `FnMut` (via `&mut`), `FnOnce` (consumes captured values). Functions implement all three.
- Capture modes follow usage; `move` forces ownership, which is what `'static` spawns need.
- Edition 2021+ captures disjoint fields of a struct instead of the whole struct (closures capture precision). This can change drop timing; be explicit when it matters.
- Pass closures as `impl Fn(...)`, generic parameters, or `Box<dyn Fn(...)>` when naming/routing is needed.
- A closure that mutates captured state cannot be called through `&self`. If a struct stores a callback, decide up front whether it is `FnMut` and expose `&mut self`.

```rust
fn retry<F: FnMut() -> Result<(), E>, E>(attempts: usize, mut f: F) -> Result<(), E> {
    for _ in 0..attempts {
        match f() { Err(e) => last = Some(e), Ok(()) => return Ok(()) }
    }
    Err(last.expect("attempts > 0"))
}
```

## Iterators

- Iterators are lazy; adapters (`map`, `filter`) do nothing until a consumer (`collect`, `sum`, `for_each`, `count`, `fold`) runs.
- `collect::<Result<Vec<_>, _>>()` short-circuits on first error — the idiomatic way to parse a sequence.
- `iter()` yields `&T`; `iter_mut()` yields `&mut T`; `into_iter()` yields `T`. On a `&Vec<T>`, `into_iter()` already yields `&T`.
- Prefer iterator chains over index loops: bounds checks usually elide and intent is clearer.
- Watch for: intermediate `collect()` followed by another iteration, `Vec` growth without `with_capacity`, and `clone()` inside adapters.
- `Vec<T>` specifics: `drain(..).for_each(...)` removes and consumes; `retain` mutates in place; `split_at_mut` yields two disjoint mutable slices (a standard borrow-checker fix).

```rust
let nums: Vec<i32> = lines.iter().map(|l| l.parse::<i32>()).collect::<Result<_, _>>()?;
let total: i32 = nums.iter().filter(|n| **n > 0).sum();
```

## Common Borrow-Checker Fights and Fixes

| Error | Typical cause | Fix |
|---|---|---|
| E0382 use of moved value | value used after pass/return | borrow it, `clone()` deliberately, or restructure ownership |
| E0499 two mutable borrows | two `&mut` into same container | split via destructuring, `split_at_mut`, iterate over fields |
| E0502 mutable + shared borrow | read while mutating | compute the read into a local first; scope the borrow |
| E0505 moved while borrowed | value dropped/moved while borrowed | clone, reorder drop, `mem::take` |
| E0515 returning local reference | returned temporary/local | return owned (`String`, `Vec`) or `Cow` |
| E0597 borrowed value does not live long enough | reference outlives source | own the data or shorten the borrow |
| E0716 temporary dropped while borrowed | binding a reference to a temporary | bind the temporary first with `let` |
| E0507 cannot move out of borrowed content | moving a field out of `&self` | `mem::take`, `Option::take`, clone, or match by reference |
| E0596 cannot borrow as mutable | binding not `mut`, or shared `&self` | add `mut`, take `&mut`, or use interior mutability |
| E0277 `Send`/`Sync` not satisfied | non-thread-safe value crosses threads | see `./03-async-concurrency.md` |
| E0106 missing lifetime | struct/fn returns borrow without source | add lifetime parameter tied to input |

```rust
// E0499 fix: split one &mut Vec into two disjoint slices
let (left, right) = data.split_at_mut(mid);
left[i] += right[j];

// E0507 fix: move a field out of &mut self
let task = self.queue.pop_front().take(); // no clone
```

Diagnosis strategy: read the compiler's "first borrow occurs here / second borrow occurs here" span pair; the fix is usually to shorten one borrow, not to fight the compiler. Add `clone()` only after you can justify why sharing is wrong.

## Anti-Patterns

- `Rc<RefCell<T>>` graphs everywhere instead of ownership boundaries or message passing.
- `clone()` to silence E0382 without understanding sharing.
- `unwrap()` on lock/parse results in library code (see `./04-error-handling.md`).
- Public structs with `pub` fields that encode invariants impossible to maintain; use constructors and accessors.
- Returning `&str`/`&T` from a function backed by an internal cache without a lifetime story.
- Overusing `'static` bounds on async traits to dodge lifetime errors.
- Index loops where iterators are clearer and safer.

## Checklist

- [ ] Types encode valid states; invalid states do not compile where practical.
- [ ] Borrows are short and scoped; no `clone()` without a stated reason.
- [ ] `Rc`/`Arc` used only for genuine shared ownership; cycles use `Weak`.
- [ ] No `std::sync` lock guard held across `.await`.
- [ ] Public enums are `#[non_exhaustive]` when extension is expected.
- [ ] Iterators replace manual index loops; no accidental intermediate collections.
- [ ] Every borrow-checker workaround is explained in code or review notes.
