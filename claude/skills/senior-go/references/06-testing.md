# Testing

Scope: table-driven tests, helpers and cleanup, fuzzing, benchmarks, golden files, HTTP testing, Testcontainers, deterministic concurrency tests, and flake elimination.

## Table-driven tests

The default shape for any function with more than two cases.

```go
func TestNormalize(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		in      string
		want    string
		wantErr error
	}{
		{name: "empty", in: "", want: ""},
		{name: "trims", in: "  a  ", want: "a"},
		{name: "rejects control", in: "a\x00", wantErr: ErrInvalid},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := Normalize(tt.in)
			if !errors.Is(err, tt.wantErr) {
				t.Fatalf("err = %v, want %v", err, tt.wantErr)
			}
			if got != tt.want {
				t.Errorf("got %q, want %q", got, tt.want)
			}
		})
	}
}
```

- `t.Run` gives isolation, filtering (`-run 'TestNormalize/trims'`), and parallel subtests. Loop variables are per-iteration since 1.22; older language versions need `tt := tt`.
- `t.Fatal` stops the current subtest; use it for setup failures, `t.Errorf` for accumulating assertion failures.
- Table fields should be explicit (`name`, `in`, `want`, `wantErr`); avoid positional anonymous structs that become unreadable.
- Prefer `errors.Is`/`errors.As` over string comparison. For deep structures, `go-cmp`:

```go
if diff := cmp.Diff(want, got); diff != "" {
	t.Errorf("mismatch (-want +got):\n%s", diff)
}
```

- `cmp.Diff` handles unexported fields via `cmpopts.IgnoreUnexported`; never add `Equal` methods just for tests.
- Fakes over mocks by default: implement the small consumer interface by hand. When you need a mock framework, `testify/mock` + generated mocks (`mockery`) or `go.uber.org/mock` are the mainstream options; keep expectations behavioral, not call-count theater.

## Helpers, cleanup, fixtures

- Mark helpers with `t.Helper()` so failures point at the caller.
- `t.Cleanup(fn)` replaces hand-rolled defers in helpers; it runs LIFO even when the test fails.
- `t.TempDir()` provides auto-removed unique directories; `t.Setenv` sets env vars and restores them (incompatible with `t.Parallel`).
- `t.Context()` (1.24+) is canceled when the test ends — use it as the parent for code under test and Testcontainers.
- Share read-only fixtures via `sync.OnceValues` at package level; never share mutable state between parallel tests.
- Test data lives in `testdata/`; the toolchain ignores that directory when building.

## Testify

- `require.*` fails fast (`FailNow`) — use for preconditions. `assert.*` records and continues — use when you want all failures in one run.
- Avoid testify's `suite` unless the lifecycle genuinely helps; `t.Run` plus helpers is simpler and plays better with `t.Parallel`.
- `testify` makes error messages concise, but the standard library's `if got != want` needs no dependency; keep assertion choices consistent within a repo.

## Golden files

For large outputs (rendered templates, codecs, CLI output), compare against checked-in golden files instead of inline strings.

```go
var update = flag.Bool("update", false, "update golden files")

func TestRender(t *testing.T) {
	got, err := Render(input)
	if err != nil {
		t.Fatal(err)
	}
	golden := filepath.Join("testdata", "render.golden")
	if *update {
		if err := os.WriteFile(golden, got, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	want, err := os.ReadFile(golden)
	if err != nil {
		t.Fatal(err)
	}
	if diff := cmp.Diff(string(want), string(got)); diff != "" {
		t.Errorf("render mismatch (-want +got):\n%s", diff)
	}
}
```

- Review golden diffs in PRs; a blind `-update` that hides a regression defeats the purpose.
- `testscript`/`txtar` is the standard-library-friendly format for scripted CLI/end-to-end tests with files.
- Normalize nondeterminism (timestamps, map order, absolute paths) before comparison.

## httptest

```go
func TestCreateOrderHandler(t *testing.T) {
	srv := httptest.NewServer(newRouter())
	defer srv.Close()

	resp, err := srv.Client().Post(srv.URL+"/v1/orders", "application/json",
		strings.NewReader(`{"name":"a"}`))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("status = %d", resp.StatusCode)
	}
}
```

- `httptest.NewRecorder` tests a single handler without a network; `NewServer` exercises middleware, routing, and real HTTP semantics.
- `NewServerTLS` for TLS paths; `srv.Client()` is preconfigured with the test certificate.
- Assert on status, headers, and decoded bodies; test auth failures and malformed JSON, not just the happy path.
- Close every response body; leaked bodies break keep-alive and hide resource bugs.

## Fuzzing

```go
func FuzzParse(f *testing.F) {
	f.Add("name=value")
	f.Add("")
	f.Fuzz(func(t *testing.T, input string) {
		v, err := Parse(input)
		if err == nil && v == nil {
			t.Fatal("nil value without error")
		}
	})
}
```

- `go test -fuzz=FuzzParse -fuzztime=30s ./pkg` explores; discovered crashers are minimized into `testdata/fuzz/` and become regression seeds.
- Seed with realistic and adversarial inputs. Add invariants (round-trip, no panic, bounded output), not just "does not crash".
- Fuzz parsers, validators, decoders, and anything consuming untrusted bytes. Keep targets fast and allocation-light.
- CI runs seed corpus (`go test ./...`) on every change and a short `-fuzztime` nightly; long campaigns run on dedicated machines. Verify current corpus-cache behavior upstream.

## Benchmarks

```go
func BenchmarkEncode(b *testing.B) {
	data := makePayload()
	b.ReportAllocs()
	for b.Loop() { // 1.24+
		if _, err := Encode(data); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkEncodeSize(b *testing.B) {
	for _, n := range []int{100, 1000, 10000} {
		b.Run(fmt.Sprintf("n=%d", n), func(b *testing.B) {
			data := makePayloadSized(n)
			b.ReportAllocs()
			for b.Loop() {
				_, _ = Encode(data)
			}
		})
	}
}
```

- `b.Loop` (1.24+) keeps the loop body live, resets the timer once, and prevents dead-code elimination. Before 1.24 use `for i := 0; i < b.N; i++` with a package-level sink to defeat elimination.
- `b.ReportAllocs()` plus `-benchmem` exposes allocations per op.
- Use `benchstat` over `-count=10` runs for comparisons; a single run is noise. Keep the machine idle and pinned, and cache binaries/inputs outside the timed loop.
- Benchmark one function per scenario; keep setup in `b.StopTimer`/`b.StartTimer` or `testing.B`-level setup.
- Profile while benchmarking: `-cpuprofile`/`-memprofile` ([./07-performance-profiling.md](./07-performance-profiling.md)).

## Deterministic concurrency and leak tests

- `testing/synctest` (stable 1.25+): run concurrent code in a bubble with a fake clock; `synctest.Wait()` blocks until every goroutine is durably blocked, making timeouts and retries deterministic. Verify the exact API shape upstream.
- `go.uber.org/goleak`: `goleak.VerifyTestMain(m)` in `TestMain` or `defer goleak.VerifyNone(t)()` catches leaked goroutines after tests.
- Replace sleeps with channel handshakes or `synctest`; `time.Sleep` in tests is a flake generator.
- Run `go test -race -count=100` for synchronization-heavy packages; `-shuffle=on` randomizes test order to expose hidden dependencies.
- See [./02-concurrency.md](./02-concurrency.md) for the concurrency primitives under test.

## Integration tests with Testcontainers

- `testcontainers-go` starts real dependencies (PostgreSQL, Valkey/Redis, Kafka, MinIO) from tests.
- Lifecycle: `testcontainers.GenericContainer` or module helpers; pass `t.Context()` to `Run` so cleanup is automatic; use `t.Cleanup` for termination.
- Wait strategies (`wait.ForLog`, `wait.ForListeningPort`, `wait.ForSQL`) instead of sleeps; module helpers provide sensible defaults.
- Reuse one container per package with `sync.OnceValues` and truncate state between tests; reuse across packages is opt-in (`TESTCONTAINERS_RYUK_DISABLED`/reuse settings — verify upstream).
- Tag integration tests with `//go:build integration` and run them in a dedicated CI job so `go test ./...` stays fast; see [./03-project-layout-tooling.md](./03-project-layout-tooling.md).
- Database-specific patterns: migrations at suite start, template databases or per-test transactions — [./05-data.md](./05-data.md).

## Organization, coverage, flakiness

| Concern | Practice |
|---|---|
| Package boundary | external `_test` package for public API tests; internal for white-box |
| Build variants | `integration`/`e2e` tags with matching CI jobs |
| Coverage | `-coverpkg=./...` for cross-package impact; `go tool cover -html`; never a target in itself |
| Caching | `go test` caches success; use `-count=1` when you suspect stale results |
| Parallelism | `t.Parallel` + `-parallel=N`; ensure port/tempfile isolation |
| Ordering | `-shuffle=on` in CI to catch inter-test coupling |

Flake causes and fixes:

- Time: fake clocks (`synctest`) or injected `Clock` interfaces.
- Ports: `:0` and read the assigned port; `httptest` does this.
- Shared state: per-test fixtures, unique DB schemas, no package-level mutable globals.
- Network: Testcontainers or fakes; never hit production in tests.
- Sleeps and retries: replace with eventual assertions (`assert.Eventually` with short interval and deadline) used sparingly and only for external systems.
- Botched cleanup: `t.Cleanup` over `defer` in helpers.

## Anti-patterns

- One giant `TestEverything` function with shared state.
- Asserting implementation details (call counts, private fields) instead of behavior.
- Testing obvious getters and generated code; no tests where a regression actually hurts.
- `time.Sleep(100 * time.Millisecond)` as synchronization.
- Mocking what you own instead of designing for testability; deep mock chains.
- Golden files regenerated on every failing run.
- Skipping `-race` because "it's slow"; marking flaky tests as skipped forever.
- Coverage theater: 100% coverage with no assertions.

## Review checklist

- [ ] Table-driven where cases multiply; subtests named and parallel-safe.
- [ ] Assertions use `errors.Is`/`cmp.Diff`; failure messages include got/want and inputs.
- [ ] Every test cleans up via `t.Cleanup`; no leaked goroutines or files.
- [ ] Fuzz targets exist for parsers/decoders; corpus committed.
- [ ] Benchmarks use `b.Loop` (or `b.N` + sink), report allocs, and are compared with benchstat.
- [ ] Integration tests tagged and run in CI with real dependencies.
- [ ] No sleeps; concurrency tested with `synctest`/goleak where applicable.
- [ ] `-race`, `-shuffle=on` and repeated `-count` runs are part of CI.
