# Dependencies and Supply Chain

Scope: dependency hygiene, lockfiles, integrity and provenance, audit workflows, patch SLAs, and defenses against typosquatting, dependency confusion, and compromised build pipelines.

## Threat Model

Your product is the transitive closure of everything you install. Real 2020s-2026 incidents came from
many directions:

| Attack | Mechanism | Defense |
|---|---|---|
| Typosquatting | Name close to a popular package (`reqeusts`, `lodahs`) | Verify names, scope registries, review before install |
| Combosquatting | `org-package-extra` names | Prefer official scoped packages |
| Dependency confusion | Internal name resolved from the public registry | Scope private names; registry pinning; allowlists |
| Maintainer account takeover | New malicious version from a trusted package | Lockfiles, delayed updates, provenance, review diffs |
| Malicious install script | `postinstall`/build script runs on install | Disable scripts where possible; sandboxed install |
| Compromised CI | Token theft publishes a poisoned version | OIDC, least privilege, pinned actions, protected branches |
| Protestware / sabotage | Maintainer intentionally breaks consumers | Vendoring/replaceable deps for critical paths |
| Abandoned package | Unpatched known CVE | Ownership review, forks, replacement plan |
| Build-time exfiltration | Compiler/plugin reaches network or secrets | Egress controls, ephemeral credentials, artifact signing |

Treat the package manager as a remote code execution channel. Minimize what you install, pin what
you keep, and verify where it came from.

## Hygiene Rules

1. **Minimize.** Every dependency is attack surface, compile time, license risk, and bytes. Prefer
   the standard library and platform APIs. Replace micro-dependencies with 20 lines of local code.
2. **Evaluate before adding.** Check: recent releases, maintainer count and responsiveness, open
   security advisories, transitive dependency count, install scripts, download provenance, and
   whether the license is acceptable. A package with one maintainer and an `postinstall` script
   deserves more scrutiny.
3. **Pin and lock.** Applications commit exactly one authoritative lockfile per project and CI
   installs strictly from it (`--frozen-lockfile`, `npm ci`, `uv sync --frozen`). Libraries publish
   compatible ranges but test against a lock.
4. **Update deliberately, not continuously.** Automated update PRs are triaged like any change:
   read the changelog, check the diff, run tests, and merge on a schedule with a rollback path.
5. **Separate dev and runtime.** Test, lint, and build tooling must not ship in runtime images or
   production environments.
6. **Prefer fewer registries.** Configure one registry per scope; never let resolution fall back
   between public and private sources for the same name.
7. **Vendor what is critical.** For release-blocking dependencies (crypto, parsers, protocol
   libraries), keep a fork or vendored copy and a documented replacement path.

## Lockfiles and Integrity

| Ecosystem | Lockfile | Strict install | Integrity mechanism |
|---|---|---|---|
| Python (uv) | `uv.lock` | `uv sync --frozen` | Hashes in lock |
| Python (pip) | `requirements.txt` with hashes (pip-tools) | `pip install --require-hashes` | `--hash=sha256:...` |
| Python (Poetry) | `poetry.lock` | `poetry install --sync` | Hashes in lock |
| Node (npm) | `package-lock.json` | `npm ci` | `integrity` (sha512) fields |
| Node (pnpm) | `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` | `integrity` fields |
| Node (yarn) | `yarn.lock` | `yarn install --immutable` | Checksums |
| Go | `go.sum` | `go mod verify`, `GOFLAGS=-mod=readonly` | Module hashes, checksum DB |
| Rust | `Cargo.lock` | `cargo build --locked` | Checksums in lock |
| Java (Gradle) | `gradle.lockfile`, dependency verification metadata | `--write-locks` in CI check mode | `verification-metadata.xml` |
| Java (Maven) | Maven resolver checksums; `versions-maven-plugin` | Reproducible builds config | `sha256`/`sha512` from repo |
| .NET | `packages.lock.json` | `dotnet restore --locked-mode` | Content hashes |

- Commit lockfiles; review lockfile diffs like code. Unexpected transitive additions are a signal.
- Enable integrity verification everywhere it exists; if the ecosystem supports a checksum database
  (Go, npm provenance, Cargo), use it.
- For browser-loaded third-party assets, use Subresource Integrity (SRI) with `crossorigin` and a
  pinned version; never `latest`.
- Track the registry and namespace for every package; document private scopes.

## Provenance and SBOM

- **Provenance** — prefer packages that publish signed build attestations (npm attestations,
  Sigstore signatures, SLSA provenance). Verify where the ecosystem supports it; treat unsigned
  packages above an uninteresting size as needing justification.
- **SLSA** — aim for level 2+ for your own artifacts (hosted build, signed provenance) and prefer
  dependencies that publish provenance. See [../../cloud/SKILL.md](../../cloud/SKILL.md) for
  platform supply-chain controls.
- **SBOM** — generate a CycloneDX or SPDX SBOM per release, attach it to the artifact, and keep it
  queryable. It is the inventory you use when the next advisory drops.
- **Signing** — sign your own artifacts (Sigstore/cosign, Signtool, GPG) and verify at deploy time;
  admission policies can reject unsigned images.
- **VEX** — when an advisory affects a component you do not use vulnerably, record a VEX statement
  instead of silently ignoring the finding.

## Audit Workflow

1. **Inventory** — SBOM plus lockfiles; know every direct and transitive component and its version.
2. **Detect** — scheduled scans plus PR-time checks: OSV-Scanner, Trivy/Grype, ecosystem tools
   (`pip-audit`, `npm audit`, `govulncheck`, `cargo audit`), and platform bots (Dependabot,
   Renovate). Include container base images and CI actions.
3. **Triage** — score with exploitability, not just CVSS: is the vulnerable function reachable, is
   the input attacker-controlled, is there a public exploit or KEV listing, what is the exposure
   (internet-facing vs internal)?
4. **Prioritize** — map to the patch SLA table below; escalate exploited or internet-facing issues
   immediately.
5. **Patch** — bump the direct dependency or use an override/patch for the transitive one; if no fix
   exists, mitigate (feature flag off, WAF rule, network isolation) and schedule removal.
6. **Verify** — tests plus a scan proving the finding is gone; confirm the fix version is what the
   lockfile resolved to.
7. **Record** — accept residual risk explicitly with an owner and expiry; suppression without an
   expiry becomes permanent debt.

### Patch SLAs (defaults; tighten for exposed systems)

| Severity / context | Target |
|---|---|
| Exploited in the wild (KEV) or public exploit, reachable | Hours; mitigate now, patch < 24 h |
| Critical, internet-facing | 24-72 h |
| Critical, internal | 7 days |
| High | 14-30 days |
| Medium | 30-90 days (next scheduled cycle acceptable) |
| Low | Next planned upgrade; track, do not block |
| EOL runtime/base image | Migrate before end-of-support; treat as high |

## Typosquatting and Dependency Confusion

- Adopt scoped names for internal packages (`@company/...`, a private index prefix) so a public
  package can never occupy the same name.
- Configure the package manager so a private scope always resolves to the private registry, and
  public scopes never fall through to internal ones.
- Publish placeholder packages on public registries for internal names you cannot scope, or reserve
  the namespace.
- Verify new dependency names character-by-character against the official documentation; do not
  trust search results, generated snippets, or LLM suggestions.
- Review lockfile changes in code review; an unexpected registry URL or integrity hash change is a
  red flag.
- Consider a private proxy/cache (Artifactory, Nexus, Cloudsmith, devpi) that allowlists sources
  and records what was fetched.

## Install and Build Hardening

| Control | Examples |
|---|---|
| Disable lifecycle scripts | npm `ignore-scripts=true`; pnpm `ignore-scripts`; Python wheels over sdists; Cargo `cargo deny` bans |
| Sandbox installs | Ephemeral container with no secrets, egress allowlist, read-only FS |
| Freeze resolution | `npm ci`, `pnpm --frozen-lockfile`, `uv sync --frozen`, `cargo --locked` |
| Pin CI actions | Full commit SHA, not tags; review updates like code |
| Least-privilege CI | `permissions: contents: read` default; OIDC per job; no long-lived cloud keys |
| Protect publish paths | 2FA, trusted publishing (OIDC), protected branches, environment approvals |
| Separate build and release | Build once, promote the same artifact; no rebuild between stages |
| Egress control | Build network restricted to registries and artifact stores |
| Reproducible builds | Pin toolchains and base images by digest; verify build inputs |

Never give a `pull_request_target` workflow a checkout of untrusted PR code with secrets in scope.
Never echo secrets into logs; mask and rotate CI variables like production credentials.

## Incident Response for a Compromised Dependency

1. Freeze deployments and dependency resolution; pin to the last known-good versions.
2. Identify exposure: which versions, which builds, which environments, which credentials the build
   could reach.
3. Treat build-time secrets as compromised; rotate and re-issue.
4. Remove or replace the package; rebuild artifacts from clean inputs; re-sign and redeploy.
5. Audit for persistence: modified CI configs, new publish tokens, changed lockfiles, unexpected
   reverse shells or scheduled jobs.
6. Publish an internal timeline and add detection (a rule, a lockfile guard) so the class is caught
   next time.

## Anti-Patterns

- Installing from unverified snippets found in issues, gists, or generated code without checking
  the package name.
- `npm install <pkg>` in production images without a lockfile or with `latest` ranges.
- Auto-merging dependency bump PRs without reading the changelog or running tests.
- Ignoring container base image and CI action updates while chasing application CVEs.
- Suppressing scanner findings permanently with no owner or expiry.
- Private package names without a scope next to a public registry.
- Storing long-lived registry/cloud tokens in CI when OIDC federation is available.
- Treating an SBOM as a compliance artifact rather than an operational inventory.

## Checklist

- [ ] Every application has one committed lockfile and CI installs strictly from it.
- [ ] Dependency additions require a documented review of maintenance, provenance, and scripts.
- [ ] Install scripts are disabled or sandboxed; builds run with no standing secrets and limited
      egress.
- [ ] Provenance/signatures are verified where the ecosystem supports them; artifacts are signed.
- [ ] An SBOM is generated per release and stored with the artifact.
- [ ] Scans run on PRs and on a schedule for OS packages, language deps, containers, and CI actions.
- [ ] Patch SLAs are documented and met; exceptions have owners and expiry dates.
- [ ] Private namespaces are scoped and registry resolution cannot fall back to public sources.
- [ ] A dependency-compromise runbook exists and has been rehearsed.
