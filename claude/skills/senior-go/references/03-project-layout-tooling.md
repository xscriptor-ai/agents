# Project Layout and Tooling

Scope: repository structure, modules and workspaces, toolchain and tool directives, linters, code generation, build tags, cross-compilation, and release mechanics for Go 1.22-1.26.

## Layout

Start with three directories; add the rest only when a concrete need appears.

```
service/
  cmd/
    api/main.go          # thin: flags, wiring, signal handling
    worker/main.go
  internal/
    httpapi/             # transport: handlers, DTOs, middleware
    order/               # domain: service, rules, errors
    storage/             # adapters: postgres, valkey
  migrations/
  testdata/
  go.mod
  go.sum
  Makefile
```

- `cmd/<binary>/` holds only `main` packages. `main` parses config, constructs dependencies, starts the server, and blocks on signals — no business logic.
- `internal/...` is enforced by the toolchain: importable only within the module subtree rooted at the `internal` directory. If you do not intend to share code, `internal` is the default.
- `pkg/` is not required by Go and buys nothing for applications; use it only when publishing a deliberate public library surface. Many teams skip it entirely.
- Name packages by what they provide (`order`, `storage`), never `util`, `common`, `helpers`, or `models`. A directory name and its package name should match; avoid stutter (`order.Order`, not `order.OrderModel`).
- Prefer package-by-feature for domains and split by layer only inside small packages. Cycles are a design smell: `domain` must not import `storage`.
- `testdata/` is ignored by the toolchain; keep fixtures there. Golden files live next to tests per [./06-testing.md](./06-testing.md).
- `api/` for OpenAPI/proto specs, `migrations/` for SQL, `docs/` for ADRs. Architecture decision records beat tribal knowledge.
- One module per independently versioned deliverable. Over-splitting into dozens of modules multiplies `go.work`, release, and tooling cost; under-splitting couples unrelated services.

## Modules

`go.mod` is the source of truth for the dependency graph; `go.sum` records hashes. Commit both.

```
module github.com/acme/service

go 1.24

toolchain go1.25.4

require (
	github.com/jackc/pgx/v5 v5.x.y
	golang.org/x/sync v0.x.y
)

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	...
)
```

- **Minimal Version Selection (MVS)** picks the maximum of the minimum versions each module requires. `go mod tidy` computes the needed set; run it after every dependency change and commit the result.
- The `go` directive is a language version **and** a strict minimum toolchain requirement since 1.21. Do not bump it casually: it changes language semantics (for example loop variables) and blocks older toolchains.
- `toolchain` line records the preferred toolchain; `GOTOOLCHAIN=auto` (default) downloads it. `GOTOOLCHAIN=local` pins CI to the installed toolchain. Verify the current policy upstream.
- `replace` is for local development and forks. Replacements are ignored in downstream modules, so never rely on them for published libraries; use `go mod edit -replace` and document.
- Semantic import versioning: after v1, major versions live in the path (`/v2`) and are separate modules. Publish tags `v2.x.y`, never move tags.
- `retract` in `go.mod` marks bad versions so consumers stop selecting them.
- `go mod tidy -diff` (1.23+) checks cleanliness in CI without writing.
- Private modules: set `GOPRIVATE=github.com/acme/*` (implies `GONOSUMDB`/`GONOSUMCHECK` behavior) and configure credentials in `~/.netrc` or git. Keep `GOSUMDB=sum.golang.org` on for public code.
- Vendoring (`go mod vendor`) is a legitimate choice for hermetic builds and regulated environments; it makes dependency diffs reviewable at the cost of repository churn.
- Diagnostics: `go mod why -m X`, `go mod graph`, `go list -m -u all`, `go version -m ./bin/app` (embedded build info).

## Workspaces

`go.work` lets multiple modules resolve each other locally without `replace` lines in every `go.mod`.

```
go 1.24

use (
	./service
	./libs/logger
)

replace github.com/acme/logger => ./libs/logger
```

- Use workspaces for multi-module repositories during active development. They are not published and do not affect consumers.
- `go work sync` aligns workspace requirements back into member `go.mod` files.
- In CI, either commit `go.work` deliberately or run with `GOWORK=off` to test the published dependency graph. Test both states if the workspace is committed.
- Avoid workspaces to patch a dependency you do not own; fork or upstream the fix instead.

## Toolchain and tools

Two ways to pin developer tooling, in order of preference:

1. **Tool directives** (Go 1.24+): `go get -tool golang.org/x/tools/cmd/stringer@latest` adds a `tool` block to `go.mod`; run with `go tool stringer`, version automatically resolved.
2. **Legacy tools.go** for older floors:

```go
//go:build tools

package tools

import (
	_ "github.com/golangci/golangci-lint/cmd/golangci-lint"
	_ "golang.org/x/vuln/cmd/govulncheck"
)
```

```bash
go run golang.org/x/vuln/cmd/govulncheck@latest ./...
```

- Pin exact versions of linters and generators in the repo; "latest" drift is a supply-chain and reproducibility risk.
- `gopls` is the standard language server; enable staticcheck diagnostics and format-on-save. Ship `.gopls`/`gopls` settings in the repo so editors converge.

## Linting and static analysis

| Tool | Catches | Notes |
|---|---|---|
| `gofmt` / `gofumpt` | formatting | mandatory, zero discussion |
| `go vet` | real correctness bugs (printf, copylocks, struct tags, lostcancel) | run in CI, not just editor |
| `staticcheck` (SA/S/ST/QF) | dead code, misuse, simplifications | high signal; wire into gopls |
| `golangci-lint` v2 | aggregates linters | config schema changed in v2; verify upstream and migrate configs |
| `govulncheck` | reachable known vulnerabilities | run in CI and on release; also [./08-observability-security.md](./08-observability-security.md) |
| `deadcode` | unreachable exported/unused code | useful when trimming APIs |
| `go fix` | modernizes idioms | modernizer set grows; verify against current toolchain |
| `gosec` | security-oriented patterns | complements, never replaces review |

CI gate: `gofmt -l .`, `go vet ./...`, `staticcheck ./...` (or golangci-lint), `go test -race ./...`, `govulncheck ./...`.

## Code generation

- Directives: `//go:generate go tool stringer -type=State`, `//go:generate go tool sqlc generate`, `//go:generate go tool buf generate`.
- Generated files start with `// Code generated by <tool>. DO NOT EDIT.` and are committed; CI regenerates and fails if `git diff` is non-empty. That keeps builds working without codegen tools installed.
- Common generators: `stringer`, `mockgen`/`moq`, `sqlc` ([./05-data.md](./05-data.md)), `oapi-codegen`, `protoc-gen-go`/`buf` ([./04-web-services.md](./04-web-services.md)), `wire` for DI.
- Keep generation hermetic: pin tool versions and input paths; never generate from network state.
- Use `//go:build ignore` on generator driver programs rather than dumping them in `main`.

## Build tags

- Use the modern `//go:build` syntax; `// +build` lines are obsolete. A blank line must separate the constraint from `package` and from doc comments.
- Standard axes: `GOOS`, `GOARCH`, `cgo`, `unix`, release tags (`go1.24`). Custom tags express build variants: `//go:build integration`, `//go:build e2e`.
- Filename conventions: `foo_linux.go`, `foo_amd64.go`, `foo_linux_amd64.go`, `foo_test.go`. Prefer filename suffixes for OS/arch; use explicit tags for variants.
- Test-only tags must pair with a CI job that actually runs them; otherwise integration tests become dead code.
- Beware `!cgo` builds silently omitting functionality (DNS resolvers, netgo); assert capabilities in tests.

## Cross-compilation and build flags

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath \
  -ldflags="-s -w -X main.version=$VERSION -X main.commit=$COMMIT" \
  -o bin/service-linux-arm64 ./cmd/api
```

- `CGO_ENABLED=0` yields static binaries; keep a `cgo` build only if you need system libraries (libsqlite, libgit2), and then test it separately.
- `-trimpath` removes local paths for reproducible builds. `-buildvcs=true` (default) stamps VCS info; disable only for hermetic reproducibility.
- `go build` is cached; `go install pkg@version` for tools. `GOFLAGS=-mod=readonly` prevents accidental `go.mod` edits in CI.
- `-gcflags=-m` for escape analysis ([./07-performance-profiling.md](./07-performance-profiling.md)); Profile-Guided Optimization uses a committed `default.pgo`.
- Reproducibility: same toolchain, `-trimpath`, pinned modules, `SOURCE_DATE_EPOCH` for archive timestamps. Verify with a second build and `go version -m`.

## Release

- Version with semver git tags: `v1.4.2`. For libraries the tag **is** the release. For applications, inject version/commit into `main` via `-ldflags -X`.
- Use GoReleaser (or an equivalent) for cross-platform archives, checksums, SBOM (`syft`), and signatures (`cosign`). Verify the current plugin set upstream.
- Containers: multi-stage build, final stage `distroless/static` or `scratch` with a non-root user, `-trimpath` binary, no shell.
- Publishing a module: push a tag, then `go list -m pkg@version` from a clean module to confirm resolution through the checksum database.
- Keep a `CHANGELOG` generated from commits or release notes; consumers need to know about `retract` and behavior changes.
- See [./08-observability-security.md](./08-observability-security.md) for signing and supply-chain controls, and [./09-ecosystem-2026.md](./09-ecosystem-2026.md) for library landscape.

## Anti-patterns

- A `util` package that imports half the repo and is imported by everything.
- `internal` used as a synonym for "ugly"; it is an API boundary, not a style label.
- Committing `go.work` with absolute local paths (or committing one at all without a reason).
- Bumping the `go` directive to get a feature without checking OS/toolchain consumers.
- Running `go mod tidy` with the network unavailable, silently dropping requirements.
- Linters pinned to `@latest`; generated code edited by hand; generator versions not pinned.
- Build-tag combinations that are never compiled in CI (dead branches).
- `-ldflags "-s -w"` without retaining debug symbols for crash triage.

## Review checklist

- [ ] Layout matches actual needs; no speculative `pkg/` or empty layers.
- [ ] `go.mod` directive floor is deliberate; toolchain pinned; `go mod tidy -diff` clean.
- [ ] Workspaces handled explicitly in CI (`GOWORK=off` where published graph must be tested).
- [ ] `gofmt`, `go vet`, `staticcheck`, `go test -race`, `govulncheck` in CI.
- [ ] Tools pinned via `tool` directives or `tools.go`; generation reproducible and committed.
- [ ] Build tags used for variant and integration coverage with matching CI jobs.
- [ ] Release artifacts reproducible, versioned, signed, SBOM-attached.
- [ ] No hand edits to generated files; no secrets in build args or tags.
