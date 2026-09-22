# Tooling and Build

Scope: cargo workspaces, feature flags and unification, profiles, task runners, lints, cross-compilation, MSRV, release automation, and supply-chain hygiene.

## Workspaces

- One workspace for related crates: a root `Cargo.toml` with `[workspace] members = ["crates/*"]`, one shared `Cargo.lock`, one `target/`.
- Resolver: edition 2024 defaults to resolver v3 (MSRV-aware feature/dependency resolution); edition 2021 defaults to v2. Set `[workspace] resolver = "3"` explicitly if members differ. Verify upstream for resolver behavior changes.
- `[workspace.dependencies]` centralizes versions; members use `dep = { workspace = true }` plus local features.
- `[workspace.package]` centralizes `version`, `edition`, `license`, `repository`, `rust-version`.
- `[workspace.lints]` (stabilized 1.74) with `[lints] workspace = true` per crate is the standard lint policy mechanism.
- Keep `Cargo.lock` committed for binaries and applications; libraries generally commit it too for reproducible CI (policy choice — document it).
- `cargo metadata --format-version 1` for tooling; `cargo tree -d` to find duplicate versions; `cargo tree -e features -i serde` to see who enables features.
- Publishing order matters; `cargo-release`, `release-plz`, or `cargo-workspaces` automate version bumps and ordered publishes.

```toml
[workspace]
members = ["crates/*"]
resolver = "3"

[workspace.package]
edition = "2024"
rust-version = "1.85"
license = "MIT OR Apache-2.0"

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
tokio = { version = "1", default-features = false }
thiserror = "2"

[workspace.lints.rust]
unsafe_op_in_unsafe_fn = "deny"

[workspace.lints.clippy]
unwrap_used = "deny"
```

## Feature Flags

- Features are additive and must never be mutually exclusive; enabling a feature must not disable another. This rule is non-negotiable for published crates.
- Feature unification: with a shared lockfile, features enabled by any member are visible to all members using that dependency. Resolver v2 avoids unifying build-dependencies/proc-macros/target-specific deps; v3 additionally prefers MSRV-compatible versions.
- Use `dep:` syntax to create features that enable optional dependencies without exposing implicit features (`serde = { version = "1", optional = true }` plus `derive = ["dep:serde"]`). `cargo` no longer creates implicit features for optional deps when `dep:` is used (verify upstream).
- Default features should be minimal and safe. `default-features = false` in libraries that want to opt in.
- Feature design table:

| Kind | Naming | Example |
|---|---|---|
| Additive capability | noun | `tls`, `http2`, `json` |
| Backend selection | `backend-<name>` | `backend-postgres` |
| Runtime selection | `rt-<name>` | `rt-tokio` |
| Unstable/experimental | `unstable-<x>` | `unstable-gats` |
| Test-only helpers | `_test-util` (underscore = internal) | `_test-util` |

- Test feature combinations with `cargo hack --feature-powerset --depth 2 test` (feature powerset can explode; limit depth) or a targeted `cargo-hack` job per combination.
- `cargo hack check --each-feature --workspace` catches features that do not compile alone.
- docs.rs: `[package.metadata.docs.rs] all-features = true` plus `rustdoc-args = ["--cfg", "docsrs"]`; crates conditionally document features with `#[cfg_attr(docsrs, doc(cfg(feature = "...")))]`.
- Optional dependencies that create feature unification hazards (e.g., a runtime) should be kept small and never enabled transitively.

## Profiles

| Profile | Defaults | Common overrides |
|---|---|---|
| `dev` | `opt-level=0`, debug info, `overflow-checks=true` | add `[profile.dev.package."*"] opt-level = 2` to speed deps |
| `release` | `opt-level=3`, no debug info, `lto=false`, `codegen-units=16` | `lto="thin"`, `codegen-units=1`, `debug=1`, `strip="debuginfo"` |
| `test` | dev-like; `cargo test --release` uses `bench`? no, use `--profile` | `[profile.test] opt-level=1` for faster integration tests |
| `bench` | release-like | `debug=true`, `lto=true` for accurate flamegraphs |

```toml
[profile.release]
lto = "thin"
codegen-units = 1
panic = "abort"      # only if no unwind boundary is required
strip = "debuginfo"  # keep symbols for profiling builds via a custom profile
overflow-checks = true

[profile.profiling]
inherits = "release"
debug = true
strip = "none"
```

- Custom profiles inherit from `dev` or `release`; use them for profiling, fuzzing, and sanitizer builds.
- `panic = "abort"` reduces size and removes unwinding; it also makes `catch_unwind` ineffective and changes FFI panic behavior. Decide per binary.
- `build-override` for build scripts and proc-macros: `[profile.release.build-override] opt-level = 3`.
- Overriding dependency optimization (`[profile.release.package."*"]`) trades build time for runtime.
- `-Zbuild-std` for custom targets stays nightly-gated in practice; verify upstream.
- Debug symbols in release: `debug = "line-tables-only"` (or `1`) balances symbol size and actionable profiles; `strip = "symbols"` for shipping binaries.

## Build Acceleration and Caching

- sccache: `RUSTC_WRAPPER=sccache`; configure a local or remote (S3/GCS) backend in CI.
- Linkers: `mold` or `lld` cut link time substantially on Linux: `RUSTFLAGS="-C link-arg=-fuse-ld=mold"` (or `rustflags` in `.cargo/config.toml`).
- cranelift backend (`-Zcodegen-backend=cranelift`) speeds debug builds on nightly; not for release artifacts.
- `cargo build --timings` and `cargo nextest` reports for build hotspots.
- Docker: `cargo-chef` to cache dependency compilation in a separate layer; build with `--locked`.
- Separate `target` dirs per profile/target in CI caches; cache keyed by `Cargo.lock` hash and toolchain.
- `cargo build --workspace --all-targets` once before parallel test jobs avoids recompilation across jobs.
- `cargo udeps` (nightly) and `cargo machete` to remove unused dependencies; both reduce compile time.

## Task Runners

| Approach | Pros | Cons |
|---|---|---|
| `just` | simple recipes, shell-friendly, widely installed | no Rust integration |
| `cargo-make` | TOML tasks, cross-platform, conditionals | verbose; plugin surface |
| `xtask` | plain Rust, typed, debuggable, no extra config | requires a workspace crate |

- `xtask` is the preferred approach for complex automation (codegen, bundling, release steps): a `crates/xtask` binary invoked as `cargo run -p xtask -- <cmd>` or aliased in `.cargo/config.toml`.
- Keep a thin `justfile`/`Makefile` as the discoverable entry point calling `cargo`/`cargo xtask`.
- CI should call the same commands developers run; no divergent CI-only scripts where avoidable.

```toml
# .cargo/config.toml
[alias]
xtask = "run --package xtask --"
ci = "clippy --workspace --all-targets --all-features -- -D warnings"
```

## Lints: rustfmt and clippy

- `rustfmt.toml`: `edition`, `max_width`, `use_small_heuristics`, `newline_style`. Note: `imports_granularity`, `group_imports`, and `style_edition` are nightly-only options; if you want them, run `cargo +nightly fmt` or avoid them.
- `clippy.toml`: `msrv`, `cognitive-complexity-threshold`, `too-many-arguments-threshold`, `disallowed-types`, `disallowed-methods`, `avoid-breaking-msg` (verify current option names upstream).
- Gate CI: `cargo clippy --workspace --all-targets --all-features -- -D warnings` and `cargo fmt --all --check`.
- Set baseline lints in the crate root (`#![deny(missing_docs, missing_debug_implementations, rust_2018_idioms)]`) and policy lints in `[workspace.lints]`.
- Common library lint set: `clippy::all`, `clippy::pedantic` (allow noisy ones explicitly), `unwrap_used`, `expect_used` (warn), `panic`, `indexing_slicing` (warn), `arithmetic_side_effects` (selective).
- `clippy::correctness` is deny-by-default; never blanket-allow it.
- Allow lints at the narrowest scope with a reason: `#[expect(clippy::cast_possible_truncation, reason = "checked above")]` (`#[expect]` supported on modern Rust; verify upstream).
- Test code may relax policy lints via `[lints]` on the test target or `#![cfg_attr(test, allow(...))]`.

## Cross-Compilation

- Install targets: `rustup target add aarch64-unknown-linux-musl x86_64-pc-windows-gnu wasm32-wasip2`.
- Static Linux binaries: `*-unknown-linux-musl` + `-C target-feature=+crt-static` (default for musl on most targets).
- Linker configuration in `.cargo/config.toml` per target; `cross` (Docker images with toolchains) or `cargo-zigbuild` (zig as cross linker) removes most sysroot pain.
- Apple targets require the Xcode SDK and license acceptance; aarch64 macOS cross from Linux is not officially supported without an SDK — use a macOS runner.
- Windows: `x86_64-pc-windows-gnu` (MinGW) cross-compiles from Linux; MSVC should run on Windows.
- WASM: `wasm32-unknown-unknown` + wasm-bindgen, or `wasm32-wasip1/wasip2` for the component model; `wasm-pack`/`cargo-component` for bundling. Verify target names and component-model status upstream.
- Test cross outputs with QEMU (`cross test --target ...`, `qemu-<arch>` binfmt) or run on matching runners.
- Check `cargo tree --target <triple>` because target-specific dependencies change feature graphs.

## MSRV (Minimum Supported Rust Version)

- Declare `rust-version` in `[package]`/`[workspace.package]`; cargo uses it for resolver v3 compatibility hints and toolchain checks.
- Test the MSRV in CI with a pinned toolchain (`actions-rs/toolchain`-style matrix or `rustup toolchain install 1.85.0`).
- `cargo-msrv` can bisect the minimal version; use it when bumping dependencies floods the MSRV.
- MSRV policy: bumping requires a semver-minor release of your library (or is a breaking change under some policies) — document the policy in the README.
- `cargo update -p <dep> --precise <version>` in CI keeps the MSRV lockfile coherent; or maintain a `Cargo.lock.msrv`.

## Release and Supply Chain

| Tool | Purpose | When |
|---|---|---|
| `cargo-deny` | advisories, bans, licenses, source allowlist | every CI run |
| `cargo-audit` | RustSec advisory DB | every CI run (or rely on cargo-deny) |
| `cargo-vet` | audit trail for dependency reviews | org policy for high-assurance |
| `cargo-udeps` | unused dependencies (nightly) | periodic |
| `cargo-machete` | unused dependencies without nightly | every CI run |
| `cargo-semver-checks` | API break detection | before release |
| `cargo-sbom` / cyclonedx | SBOM generation | release artifacts |

```toml
# deny.toml (abridged)
[advisories]
version = 2
yanked = "warn"

[licenses]
allow = ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC", "Unicode-3.0"]
confidence-threshold = 0.93

[bans]
multiple-versions = "warn"
wildcards = "deny"

[sources]
unknown-registry = "deny"
unknown-git = "deny"
```

- Lockfile: `cargo build --locked` in CI and release; `cargo update` is a reviewed PR, never silent.
- Vendoring for hermetic builds: `cargo vendor` and `[source.crates-io] replace-with = "vendored-sources"`.
- `cargo publish --dry-run` before release; publish with `--locked` (supported by modern cargo; verify upstream).
- crates.io trusted publishing (OIDC-based CI publishing) exists on the modern registry; verify upstream before adopting, and prefer it to long-lived tokens.
- Tag releases, attach checksums/SBOM, and sign when the org requires it (Sigstore/cosign is common).
- Reproducibility: pin toolchain (`rust-toolchain.toml`), commit lockfile, use `--locked`, set `SOURCE_DATE_EPOCH` where applicable, and avoid path-dependent build scripts.
- Security response: watch RustSec advisories, have an update path for transitive deps, and CI-fail on new advisories (`cargo-deny check advisories`).

## Anti-Patterns

- Always-on `[features] default = ["full"]` that pulls TLS, DB drivers, and runtimes into every consumer.
- Mutually exclusive features ("enable exactly one backend") that only work by convention.
- Cargo.lock ignored in a binary repository.
- `-D warnings` on rustc but not clippy, or clamping the toolchain without pinning it.
- Cross-compiling without testing the artifact.
- Committing `cargo vendor` trees without an update process.
- Long-lived crates.io tokens in CI.
- Relying on `cargo update` to silently fix advisories in production releases.

## Checklist

- [ ] Workspace resolver matches the edition; shared deps/lints centralized.
- [ ] Features are additive and documented; powerset check runs in CI.
- [ ] Release/profile settings deliberate (`lto`, `codegen-units`, `panic`, `strip`, `debug`).
- [ ] Lint policy in `[workspace.lints]`; CI runs fmt + clippy with `-D warnings`.
- [ ] Cross targets built and smoke-tested where shipped.
- [ ] MSRV declared, pinned, and tested.
- [ ] `cargo-deny`/`cargo-audit` and `cargo-semver-checks` in CI; release uses `--locked`.
- [ ] Build cache configured; clean-checkout build time measured.
- [ ] Release process automated (version bump, changelog, publish order, artifacts).
