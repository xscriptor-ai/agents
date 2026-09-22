# Secure Code Review and Security Testing

Scope: a repeatable secure code review process, per-class review checklists, security-focused test techniques, threat-driven test cases, and CI gates that keep fixes in place.

## Review Goals

A secure review answers four questions for every change:

1. **What new data reaches what interpreter or trust boundary?** (Injection, deserialization, SSRF.)
2. **Who can call this, and what can they reach?** (Authentication, authorization, tenancy.)
3. **What can an attacker learn or force?** (Disclosure, DoS, races, error handling.)
4. **What assumptions does it add to the system, and are they tested?** (Config, dependencies,
   crypto, invariants.)

Static analysis finds patterns; only a human (or a threat-driven test) answers whether the
authorization check covers the object in question. For threat modeling depth, see
[../../security/SKILL.md](../../security/SKILL.md).

## Review Process

1. **Scope the diff.** Identify routes, jobs, and consumers touched; note new dependencies, config,
   permissions, and serialization formats.
2. **Map data flows.** For each new input, trace source -> transforms -> sinks. Mark trust
   boundaries: HTTP, queue, database row from another tenant, third-party API, file, URL fetch.
3. **Check authorization per entry point.** Enumerate actors and verify object-scoped checks, not
   just route-level middleware. Look for IDOR patterns (`get(id)` without a tenant filter).
4. **Review sinks against the class tables below.** Use `git diff`-focused review for changes and a
   lighter full-service pass periodically.
5. **Verify failure modes.** Force errors: dependency down, malformed input, partial writes,
   concurrent requests, expired tokens. Confirm fail-closed behavior.
6. **Check tests.** Every fix and every sensitive path needs a security-relevant test (below).
7. **Record findings** with severity, exploit narrative, location, and a concrete fix. Re-review the
   fix and confirm the regression test fails without it.
8. **Add prevention.** When the same defect class appears twice, add a lint/SAST rule or a shared
   helper so the pattern becomes hard to repeat.

## High-Risk Diff Signals

Scan new code for these greppable patterns before anything else:

- String formatting near interpreters: `f"`, `%s` with `%`, `+`, `format(`, template literals next
  to `query`, `execute`, `exec`, `system`, `spawn`, `render`, `compile`.
- Raw/unsafe escape hatches: `raw(`, `text(`, `$queryRawUnsafe`, `createNativeQuery`, `literal(`,
  `sql.raw`, `eval`, `Function(`, `vm.run`, `os.system`, `shell=True`, `pickle`, `Marshal`,
  `unserialize`, `ObjectInputStream`, `BinaryFormatter`.
- Authz gaps: routes without the policy/middleware decorator; lookups by ID without owner/tenant
  scope; admin checks done in the UI only; `is_staff` vs object permission confusion.
- Secrets: committed config, tokens in logs, long-lived credentials, new environment variables
  without a manager, `.env` in an image layer.
- Network: new outbound fetch of user URLs, disabled TLS verification, `*` CORS, `0.0.0.0` binds.
- Crypto: `md5`, `sha1`, `ECB`, `CBC` without MAC, static IV, `Math.random`, `rand()`, `==` on MACs.
- Files: upload handlers, archive extraction, path joins, `send_file` with user paths.
- Dependencies: new package, version change, lockfile churn with new transitive entries.
- CI: workflow changes, new tokens/permissions, `pull_request_target`, unpinned actions.

## Per-Class Checklist

### Authentication and session

- [ ] Credentials verified with a password-hashing library and constant-time comparison.
- [ ] Session identifiers are CSPRNG, rotated on login and privilege change, and invalidated on logout.
- [ ] Cookies carry `HttpOnly`, `Secure`, `SameSite`, and a `__Host-` prefix where applicable.
- [ ] Password reset and email verification tokens are single-use, expiring, hashed at rest.
- [ ] MFA bypass paths, "remember me", and recovery flows have explicit tests.
- [ ] JWT/OAuth tokens verify signature, algorithm allowlist, issuer, audience, and expiry.

### Authorization

- [ ] Every endpoint and background consumer enforces authorization server-side.
- [ ] Object access filters include owner/tenant scope in the query, not after the fetch.
- [ ] Role changes, account deletion, and privilege transitions invalidate cached decisions.
- [ ] Admin/internal endpoints are isolated (network and role) and audited.
- [ ] Tests prove one tenant cannot read or mutate another tenant's objects.

### Injection and interpreters

- [ ] Values are bound; identifiers/sort/operators come from allowlists
      ([./01-injection.md](./01-injection.md)).
- [ ] No shell with user data; argv arrays, absolute binaries, `--` terminators.
- [ ] Templates render data, never compile user input.
- [ ] LDAP/XPath filters are escaped or library-built.

### Browser-facing

- [ ] Context-aware encoding at every sink; no raw HTML sinks with untrusted data
      ([./02-xss-csrf.md](./02-xss-csrf.md)).
- [ ] CSP (nonce-based), Trusted Types, and the security header baseline are set and tested.
- [ ] CSRF protection covers all state-changing routes, including login/logout.
- [ ] CORS uses an exact allowlist with `Vary: Origin`; credentials only where required.

### Data protection and crypto

- [ ] AEAD with unique nonces; keys from a KMS; rotation defined
      ([./04-crypto-secrets.md](./04-crypto-secrets.md)).
- [ ] Passwords use Argon2id/scrypt/bcrypt with tuned parameters and lazy rehash.
- [ ] Secrets absent from code, images, logs, and client bundles; CI scans history.
- [ ] PII is minimized, encrypted at rest where required, and access is audited.

### Input, files, and paths

- [ ] Boundary schemas validate type/length/range/enum and reject unknown fields
      ([./05-validation-encoding.md](./05-validation-encoding.md)).
- [ ] Uploads are content-sniffed, re-encoded, randomly named, stored inert, served safely.
- [ ] Path parameters resolve inside a base directory after symlink resolution.
- [ ] Decompression, regex, and parser resources are bounded.

### Network and serialization

- [ ] User-controlled outbound URLs are scheme/IP/redirect validated with egress controls
      ([./03-ssrf-deserialization.md](./03-ssrf-deserialization.md)).
- [ ] No native deserialization of untrusted data; signed state is verified before parsing.
- [ ] Webhooks verify signatures and timestamps with replay protection.

### Resilience and observability

- [ ] External calls have timeouts, retries with jitter and caps, and circuit breakers.
- [ ] Race-prone operations use transactions, locks, or atomic compare-and-set.
- [ ] Errors to clients are generic; logs capture detail without secrets or full payloads.
- [ ] Security events (auth failures, permission denials, admin actions) are audited with actors.

### Dependencies and configuration

- [ ] Lockfile updated intentionally; new packages reviewed
      ([./07-dependencies.md](./07-dependencies.md)).
- [ ] Default credentials and debug modes are off; config validation fails startup on insecure values.
- [ ] Infrastructure changes have least-privilege IAM and no public exposure by default.

## Security-Focused Tests

Security tests are ordinary tests aimed at abuse cases. They belong in the same suites and CI runs
as functional tests so they cannot rot.

| Technique | Catches | Practical use |
|---|---|---|
| Unit abuse tests | Injection, encoding, authz logic | Hostile payload per sink/route |
| Property-based tests | Parsers, canonicalization, invariants | Hypothesis/fast-check/proptest generators |
| Fuzzing | Memory safety, parser crashes, logic edge cases | libFuzzer/AFL++/cargo-fuzz/go-fuzz/Jazzer/Atheris |
| SAST | Unsafe patterns at scale | Semgrep, CodeQL, Bandit, gosec, SpotBugs+FindSecBugs, clippy |
| SCA | Known vulnerable dependencies | OSV-Scanner, Trivy, ecosystem audits |
| Secret scanning | Credential leakage | gitleaks, TruffleHog, provider scanning |
| IaC scanning | Cloud/Kubernetes misconfig | Checkov, Trivy config, kube-linter |
| DAST | Runtime issues on a live app | ZAP, Burp, authenticated scans in staging |
| Sanitizers | Memory/UB/thread errors in native code | ASan, UBSan, MSan, TSan |
| Contract/authz matrices | Broken access control | Parameterized tests across roles and tenants |

Rules for security tests:

- Write them from the attacker's perspective: "user A requests B's object", "payload contains
  `</script>`", "URL redirects to metadata", not just "input is rejected".
- Pin the original vulnerability payload as a regression test for every fixed finding.
- Keep them fast and deterministic; flaky security tests get disabled, which means they do not exist.
- Run SAST/SCA plus the abuse tests on every pull request; run fuzzing/DAST on a schedule and before
  major releases.

## Threat-Driven Test Cases

Derive tests from STRIDE per component rather than from a generic checklist (depth in
[../../security/SKILL.md](../../security/SKILL.md)).

| Threat | Test an attacker would run |
|---|---|
| Spoofing | Forged/expired/`alg:none` tokens; replayed webhooks; session fixation; MFA downgrade |
| Tampering | Modified signed state, price/quantity fields, hidden fields, path traversal, mass assignment |
| Repudiation | Actions without audit trail; logs missing actor, timestamp, or outcome |
| Information disclosure | IDOR across tenants; verbose errors; directory listing; cache-debug headers; SSRF readback; timing oracles |
| Denial of service | Oversized bodies, deep JSON, ReDoS, zip bombs, unbounded pagination, expensive unauthenticated endpoints, lock contention |
| Elevation of privilege | Role field injection, admin route reachable by normal user, JWT claim trust, SSRF to internal admin APIs |

Also test the boring abuse cases: double-spend/duplicate submission (idempotency), coupon/credit
reuse, enum-based state machine skips, concurrent updates losing data, and account enumeration via
timing or message differences.

## CI Gates and Suppression Policy

| Gate | Stage | Failure mode |
|---|---|---|
| Secret scan | Commit/PR | Block on any hit; rotate if real |
| SAST (high severity) | PR | Block on new findings; baseline legacy with expiry |
| SCA (critical/high reachable) | PR + nightly | Block per deployment policy; nightly for base images |
| IaC scan | PR for infra dirs | Block on high severity |
| Abuse/regression tests | PR | Block |
| Fuzzing smoke | PR for parser changes | Block on crashes; longer runs nightly |
| DAST | Staging deploy | Block promotion on high findings |

Suppression rules: every ignore needs a reason, an owner, a link to the ticket, and an expiry date
(90 days default). Findings on internet-facing code are never suppressed by default. Track metrics
that drive behavior: mean time to patch by severity, repeat defect classes, and percent of PRs with
security-relevant tests.

## Finding Writeup Format

```
Title:      <class> in <component> allows <impact>
Severity:   critical | high | medium | low (with rationale)
Location:   path/file.ext:line
Actor:      unauthenticated | any user | tenant A | insider
Narrative:  steps from request to impact
Evidence:   payload, test, or tool output
Fix:        concrete change, plus the test that proves it
Prevention: lint/SAST rule, shared helper, or guideline update
```

## Review Sign-Off Checklist

- [ ] Data flows traced for all new inputs; every sink mapped to a control.
- [ ] Authorization verified per object and per action, including background jobs and exports.
- [ ] Failures fail closed; errors and logs do not leak secrets or internals.
- [ ] Crypto, randomness, and secret handling follow [./04-crypto-secrets.md](./04-crypto-secrets.md).
- [ ] Files, paths, uploads, and outbound fetches follow [./05-validation-encoding.md](./05-validation-encoding.md)
      and [./03-ssrf-deserialization.md](./03-ssrf-deserialization.md).
- [ ] Dependencies, lockfiles, and CI changes reviewed
      ([./07-dependencies.md](./07-dependencies.md)).
- [ ] Abuse tests and a regression test for each fixed finding are present and run in CI.
- [ ] Residual risk is documented with an owner and an expiry; suppressions expire.
