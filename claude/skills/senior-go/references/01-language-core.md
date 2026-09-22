# Language Core

Scope: modern Go language mechanics — generics, stdlib collection helpers, iterators, errors, defer/panic, struct tags, embedding, zero values, and the footguns that survive into production.

## Generics

Generics (1.18+) are for algorithms and containers over homogeneous types; interfaces remain the tool for polymorphic behavior.

```go
func Map[S ~[]E, E, R any](in S, f func(E) R) []R {
	out := make([]R, len(in))
	for i, v := range in {
		out[i] = f(v)
	}
	return out
}

func Sum[T cmp.Ordered](vals ...T) T {
	var zero T
	for _, v := range vals {
		zero += v
	}
	return zero
}
```

Rules that matter in review:

- Constraints use type sets: `~int` accepts defined types whose underlying type is `int`. Use `cmp.Ordered` for `<`-comparable types; `comparable` only permits `==`/`!=`.
- Methods cannot declare their own type parameters. If a method needs one, write a generic function or a generic type.
- `T` may be a pointer type, so `if v == nil` only compiles when the constraint allows it (for example `interface{ ~*S }` or a concrete pointer); a bare `any` cannot be compared structurally.
- Inference fails on return types; annotate explicitly at call sites, e.g. `Map[[]int, int, string](...)` when the function argument is not enough.
- Generic type aliases require Go 1.24+; before that, aliases could not be parameterized. Verify the floor in `go.mod`.
- Do not genericize for one caller. A concrete function plus duplication beats an unreadable constraint lattice. See [./09-ecosystem-2026.md](./09-ecosystem-2026.md) for library alternatives.

## Slices, maps, cmp helpers

The `slices`, `maps`, and `cmp` packages (1.21+) replace most hand-rolled loops and `sort.Slice` (which is still fine for one-off `Less` closures).

| Need | Use | Instead of |
|---|---|---|
| Membership | `slices.Contains` | manual loop |
| Sort by key | `slices.SortFunc(xs, func(a, b T) int)` | `sort.Slice` |
| Sort ascending | `slices.Sort` | `sort.Ints/Strings` |
| Binary search | `slices.BinarySearch` | `sort.Search` |
| Remove dupes (sorted) | `slices.Compact` | map round-trip |
| Remove by predicate | `slices.DeleteFunc` | filter loop |
| Copy before mutation | `slices.Clone` | `append([]T(nil), s...)` |
| Preallocate | `slices.Grow(s, n)` | `make` + `copy` gymnastics |
| Map key/value snapshots | `maps.Keys`/`maps.Values` + `slices.Collect` | map loops |
| Compare maps | `maps.Equal` | `reflect.DeepEqual` |
| First non-zero | `cmp.Or(a, b, c)` | nested `if` |

Builtins `min`, `max`, `clear` (1.21+) apply to ordered types, and `clear` empties maps/slices. For strings, prefer `strings.Cut` over `SplitN`+indexing and `strings.Builder` over `+=` in loops. `bytes.Clone` avoids retaining large backing arrays when slicing.

Allocation traps: `maps.Keys` is lazy (an iterator) and must be collected; `slices.DeleteFunc` zeroes removed slots to release pointers; `slices.Clip` releases spare capacity when retaining a small prefix of a large slice.

## Iterators and range-over-func

Go 1.23 added `iter.Seq[V]` and `iter.Seq2[K,V]` with `for range` support. A `Seq` is `func(yield func(V) bool)`; return `false` from `yield` to stop. Standard producers: `slices.Values`, `slices.All`, `maps.All`, `strings.Lines`/`SplitSeq` (1.24+).

```go
func Count[T comparable](seq iter.Seq[T], want T) int {
	n := 0
	for v := range seq {
		if v == want {
			n++
		}
	}
	return n
}

func ReadAll(r io.Reader) iter.Seq2[[]byte, error] { /* batched reads */ }
```

Patterns:

- Pull-style consumption from a push iterator: `next, stop := iter.Pull(seq); defer stop()`.
- Materialize with `slices.Collect(seq)`, `slices.Sorted(maps.Keys(m))`, or `slices.AppendSeq(dst, seq)`.
- Return errors per element with `Seq2[V, error]`; the caller stops on the first error.
- Convert a channel to an iterator only if the channel is closed; a nil channel blocks forever.
- Iterators are lazy and single-use; documenting ownership matters as much as for channels.
- `for range 10` (range over `int`) requires 1.22+ and is the idiomatic "do n times".

Loop-variable semantics: since 1.22 each iteration has fresh variables, so closures and `&v` are safe. Modules declaring an older `go` version keep the old behavior unless you set `GODEBUG=loopvar=1`; check `go.mod` before "fixing" captures. See [./02-concurrency.md](./02-concurrency.md) for how this interacts with goroutines in loops.

## Errors

Three mechanisms, used deliberately: sentinels for conditions callers branch on, typed errors for structured data, wrapping for context.

```go
var ErrNotFound = errors.New("not found")

type ValidationError struct {
	Field string
	Err   error
}

func (e *ValidationError) Error() string { return "invalid " + e.Field + ": " + e.Err.Error() }
func (e *ValidationError) Unwrap() error { return e.Err }

func Load(ctx context.Context, id string) (*Record, error) {
	rec, err := db.Get(ctx, id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("load record %q: %w", id, ErrNotFound)
		}
		return nil, fmt.Errorf("load record %q: %w", id, err)
	}
	return rec, nil
}
```

- Wrap with `%w` when the caller may need `errors.Is`/`errors.As`; use `%v` when you deliberately break the chain.
- Multiple `%w` verbs (1.20+) and `errors.Join` create multi-error trees that `errors.Is` traverses.
- Implement `Is`/`As` methods on custom error types to compare by logical identity while retaining wrapping.
- `errors.As` requires a pointer to the target type: `var ve *ValidationError; errors.As(err, &ve)`.
- `errors.Is(err, nil)` is false; check `err != nil` first, and never `==` compare wrapped errors.
- Error strings are lowercase, no trailing punctuation, and carry the failing operation ("decode config: unexpected EOF"). They must not contain secrets or user payloads.
- Do not log and return; let the owner of the request decide severity. Libraries never call `log.Fatal`/`os.Exit`.
- `panic` is for programmer errors and unrecoverable invariants. `recover` only works in a directly deferred function; use it at process boundaries (HTTP middleware, goroutine roots), never as control flow. Panics from goroutines cannot be recovered by another goroutine's `recover`.
- `github.com/pkg/errors` is obsolete: `fmt.Errorf` with `%w` covers its use cases. Verify in [./09-ecosystem-2026.md](./09-ecosystem-2026.md).

## Defer semantics

- Deferred calls run LIFO when the surrounding function returns, panics, or `runtime.Goexit`s — but not on `os.Exit`.
- Arguments (including method receivers) are evaluated at the `defer` statement, not at execution:

```go
for i := 0; i < 3; i++ {
	defer fmt.Print(i) // prints 210
}

m := &Metrics{}
defer m.Close() // receiver captured now; later m = nil does not matter
```

- Named results can be observed and modified by deferred functions, which enables `defer func() { err = errors.Join(err, tx.Rollback()) }()`.
- Modern compilers open-code defers in straight-line functions; a `defer` inside a loop still allocates and fires only at function exit. To release per-iteration resources, wrap the body in a closure/function call.
- `recover` must be called directly in the deferred function; `defer recover()` works but discards the panic info.

## Struct tags and JSON

Tags are metadata conventions, not a type system. Validate them with `go vet`'s structtag analyzer.

```go
type Event struct {
	ID        string    `json:"id"`
	Type      string    `json:"type"`
	CreatedAt time.Time `json:"created_at"`
	Payload   []byte    `json:"-"`
	Score     float64   `json:"score,omitempty"`
	Updated   time.Time `json:"updated,omitzero"` // 1.24+
}
```

- `omitempty` omits zero values (empty string, 0, empty slice/map, nil pointer); `omitzero` (1.24+) uses the `IsZero` method and covers `time.Time`.
- Only exported fields are marshaled; embedded structs flatten by default.
- `encoding/json` matches field names case-insensitively when no tag exists, which hides contract drift — always tag wire types.
- Unknown fields are ignored by default; use `Decoder.DisallowUnknownFields` when consuming first-party JSON.
- For databases use `db`/`pgx` tags, validation uses `validate`, config uses `koanf`/`env`, and YAML uses `yaml`. One struct per boundary; do not overload one struct with five tag dialects.
- Custom `MarshalJSON`/`UnmarshalJSON` must handle nil receivers and avoid infinite recursion by aliasing the type.

## Embedding

- Embedding promotes fields and methods; the outer type satisfies embedded interfaces.
- Conflicts: if two embedded types promote the same name at the same depth, selection is ambiguous and fails to compile; qualify explicitly.
- Embedding is not inheritance: the outer value does not become the inner type for assignment or `errors.As` unless you implement `Unwrap`/`As`.
- Embedding a concrete type in a test double silently inherits real behavior. Embed the interface you are faking instead.
- Never embed `sync.Mutex` in an exported struct: `Lock()` becomes part of the public API and the struct becomes non-copyable. Use a named field.
- Embedding `sync.Mutex` also trips copylocks vet checks when the struct is copied.

## Zero values

Design for usable zero values where the type allows it: `bytes.Buffer`, `sync.Mutex`, `sync.Once`, `slog.Logger` values, and most slices/maps.

| Zero value | Behavior |
|---|---|
| nil slice | `len` 0; `append` allocates; ranging is fine |
| nil map | reads return zero, `delete` is fine, **write panics** |
| nil channel | send/receive block forever; `close` panics; use in `select` to disable a case |
| nil func | calling panics |
| nil interface | holds no type; a typed nil pointer inside an interface is **not** nil |
| zero `time.Time` | `IsZero`; not the Unix epoch |

The typed-nil-in-interface trap is the most common production bite: return `nil` explicitly, not a typed nil pointer, or check with reflection/`IsZero`.

## Footguns

- `append` aliasing: two slices can share a backing array after `s1 = append(s1, x)`; clone at API boundaries when ownership transfers.
- `range` copies each element; mutating `for _, v := range s` loops silently edits copies. Use index assignment.
- Map iteration order is randomized; never rely on it for output stability. Sort keys.
- Integer conversions truncate and overflow silently; bound before converting, and use `math`/`strconv` helpers.
- `==` on floats, `time.Time` (monotonic + location), and structs containing uncomparable fields (slices, maps, funcs) fails or misbehaves; use `Equal`/`cmp.Compare`.
- Shadowing with `:=` inside `if`/`for` hides outer variables; enable `shadow` checks in review for critical paths.
- String concatenation in loops allocates quadratically; use `strings.Builder` with `Grow`.
- Taking the address of a range variable: safe since 1.22, but still surprising when the pointer outlives the loop and the module targets an older language version.
- `init()` with I/O, goroutines, or flag registration makes tests order-dependent; prefer explicit constructors.
- Comparing errors with `==` where wrapping is possible; always `errors.Is`.

## Review checklist

- [ ] Constraint is minimal (`comparable`, `cmp.Ordered`, exact method set) and the generic actually has two or more call sites.
- [ ] Collection operations use `slices`/`maps`/`cmp` rather than hand loops where clearer.
- [ ] Iterator functions stop on `yield == false` and document ownership/single-use.
- [ ] Every error is wrapped with operation context, and callers branch with `errors.Is`/`errors.As`.
- [ ] `defer` argument-evaluation semantics are understood where mutation is involved.
- [ ] Wire structs are tagged; unknown fields rejected on inbound JSON where appropriate.
- [ ] Embedded types are intentional; no embedded mutexes or inherited test doubles.
- [ ] No typed-nil interface returns; zero values documented when unusual.
