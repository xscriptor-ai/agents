# OWASP

> Scope: using OWASP artifacts as a requirements and triage backbone — Top 10, ASVS, API Security Top 10, LLM Top 10, and mapping findings to verifiable controls.

## How to use OWASP artifacts

OWASP produces several families of documents with different jobs. Do not treat the Top 10 as a standard; treat it as awareness and prioritization. Use ASVS as the requirement catalog, the API Security Top 10 for API programs, and the LLM Top 10 for AI features.

| Artifact | Job | Audience |
|---|---|---|
| Top 10 | Awareness and risk framing | Everyone, especially product and management |
| ASVS | Verifiable security requirements by level | Engineers, testers, architects, assessors |
| API Security Top 10 | API-specific risk framing | API and platform teams |
| LLM Top 10 | AI feature risk framing | AI/ML and application teams |
| Testing Guide (WSTG) | How to verify web controls manually | Testers, red teams |
| Cheat Sheet Series | Implementation guidance per topic | Engineers |
| SAMM | Program maturity model | Security leadership |

OWASP refreshes the Top 10 on a multi-year cycle; verify the current edition upstream before citing categories. The 2025 edition reorganized several 2021 entries (see the mapping below). ASVS is on a 5.x line; verify the current chapter set upstream.

## OWASP Top 10

| # | Risk | What it looks like | Primary controls |
|---|---|---|---|
| A01 | Broken Access Control | IDOR, missing function-level checks, forced browsing | Deny by default, centralized policy decision, object-level checks, server-side enforcement |
| A02 | Security Misconfiguration | Default accounts, verbose errors, open buckets, permissive CORS | Hardened baselines, config as code, environment separation, minimal features, no stack traces to users |
| A03 | Software Supply Chain Failures | Malicious or compromised dependency, tampered build, unsigned artifact | SBOM, provenance, signing, pinned deps, see `./06-supply-chain.md` |
| A04 | Cryptographic Failures | Plaintext transport/storage, weak hashing, hardcoded keys | TLS everywhere, AEAD, Argon2id, managed keys, see `./07-crypto.md` |
| A05 | Injection | SQL/NoSQL/OS/LDAP injection, template injection (SSTI), XSS as edge case | Parameterized queries, typed APIs, input validation, context-aware output encoding |
| A06 | Insecure Design | No threat model, unbounded trust, missing abuse controls | Threat modeling at design time, secure patterns, requirement-level abuse cases, see `./01-threat-modeling.md` |
| A07 | Authentication Failures | Credential stuffing, weak reset flows, session fixation | MFA/passkeys, rate limiting, secure session lifecycle, see `./03-authn-authz.md` |
| A08 | Software and Data Integrity Failures | Unsigned updates, deserialization of untrusted data, CI tampering | Signed artifacts, safe serializers, integrity checks, protected CI, see `./06-supply-chain.md` |
| A09 | Logging and Alerting Failures | No audit trail, unmonitored auth events, logs tamperable | Structured event logs, central pipeline, alerts on security events, see `./09-incident-response.md` |
| A10 | Mishandling of Exceptional Conditions | Failing open, unhandled errors leaking state, resource exhaustion on error paths | Fail-closed defaults, typed errors, safe error responses, bounded retries and resources |

### 2021 to 2025 mapping (orientation only)

| 2021 | 2025 direction |
|---|---|
| A01 Broken Access Control | A01 Broken Access Control (stable) |
| A02 Cryptographic Failures | A04 Cryptographic Failures |
| A03 Injection | A05 Injection |
| A04 Insecure Design | A06 Insecure Design |
| A05 Security Misconfiguration | A02 Security Misconfiguration (rank up) |
| A06 Vulnerable and Outdated Components | A03 Software Supply Chain Failures (broadened) |
| A07 Identification and Authentication Failures | A07 Authentication Failures |
| A08 Software and Data Integrity Failures | A08 Software and Data Integrity Failures |
| A09 Security Logging and Monitoring Failures | A09 Logging and Alerting Failures |
| A10 SSRF | Folded into access control and out-of-band request guidance |
| — | A10 Mishandling of Exceptional Conditions (new) |

Do not re-map a program wholesale just because ranks move; use the change list to update requirements and test coverage where categories gained or lost scope.

## ASVS levels

ASVS states requirements as verifiable statements organized by chapter, each tagged with a level. Levels are cumulative.

| Level | Meaning | When to target |
|---|---|---|
| L1 | Baseline, mostly testable without deep expertise | Every application, including internal |
| L2 | Defense in depth for applications handling sensitive data | Most business applications, customer data, regulated data |
| L3 | High assurance, resistant to advanced threats | Critical infrastructure, health, finance, high-value transactions |

Practical adoption:

1. Pick the target level per application from data classification and exposure, not from ambition.
2. Turn the chosen requirements into tickets and test cases; ASVS is testable by design.
3. Start with the authentication, session management, access control, validation, and crypto chapters; they remove the most risk per unit of effort.
4. Record out-of-scope requirements and L3 gaps as owned exceptions.
5. Reassess when exposure or data class changes; a tool that becomes internet-facing jumps to L2/L3 obligations.

Common chapter themes: architecture and threat modeling, authentication, session management, access control, input validation and encoding, stored cryptography, error handling and logging, data protection, communications, malicious code and supply chain, business logic, file handling, API and web service, configuration, and (in 5.x) data layer and application security posture themes. Verify the exact chapter list upstream.

## API Security Top 10

| # | Risk | Example | Control |
|---|---|---|---|
| API1 | Broken Object Level Authorization | `GET /orders/123` returns another user's order | Per-object authorization on every access |
| API2 | Broken Authentication | Weak token issuance, no revocation, credential stuffing | Strong authn, short tokens, rotation, rate limits |
| API3 | Broken Object Property Level Authorization | Mass assignment or excessive data exposure | Explicit allowlists for writable and readable fields |
| API4 | Unrestricted Resource Consumption | No pagination/limits; billable third-party calls | Quotas, pagination caps, timeouts, cost limits |
| API5 | Broken Function Level Authorization | Regular user reaches admin endpoint | Function-level policy, deny by default, no hidden routes |
| API6 | Unrestricted Access to Sensitive Business Flows | Scalping, spam, abuse of a legitimate flow | Flow-specific controls, velocity limits, human checks |
| API7 | Server-Side Request Forgery | URL parameter fetches internal metadata | Egress allowlist, no user-controlled egress, metadata protections |
| API8 | Security Misconfiguration | Verbose errors, permissive CORS, missing headers | Hardened gateway config, consistent error contract |
| API9 | Improper Inventory Management | Shadow and deprecated API versions exposed | Version registry, deprecation policy, gateway inventory |
| API10 | Unsafe Consumption of APIs | Trusting upstream API data blindly | Validate and sanitize third-party responses, TLS pinning where warranted |

API design specifics belong in an API-design pack; this reference only fixes the risk-to-control mapping. See `./03-authn-authz.md` for token and scope handling and `./04-security-architecture.md` for gateway and policy placement.

## LLM Top 10

The LLM list tracks AI feature risks; full treatment is in `./08-llm-security.md`.

| # | Risk | One-line control |
|---|---|---|
| LLM01 | Prompt Injection | Treat model input/output as untrusted; constrain privileges and tools |
| LLM02 | Sensitive Information Disclosure | Minimize context, filter outputs, tenant-isolate retrieval |
| LLM03 | Supply Chain | Vet models, datasets, plugins, and serving stacks; attest artifacts |
| LLM04 | Data and Model Poisoning | Provenance, curation, anomaly detection on training/retrieval data |
| LLM05 | Improper Output Handling | Validate and encode before any downstream sink |
| LLM06 | Excessive Agency | Least-privilege tools, human approval, bounded autonomy |
| LLM07 | System Prompt Leakage | No secrets in prompts; assume prompts are public |
| LLM08 | Vector and Embedding Weaknesses | Access control at retrieval, embedding hygiene, poisoning checks |
| LLM09 | Misinformation | Grounding, citations, confidence surfacing, human review for high stakes |
| LLM10 | Unbounded Consumption | Quotas, token and cost caps, timeouts, abuse monitoring |

An Agentic Security Initiative body of work extends this to autonomous agent risks; verify its current status upstream and load it when agents hold credentials or act without a human in the loop.

## Mapping findings to controls

Use one pipeline for scanner output, pen-test reports, and bug bounties so fixes are comparable and trackable.

1. **Reproduce and scope.** Confirm the finding against a running artifact; note entry point, authentication required, and affected data.
2. **Classify.** Map to the OWASP category and the underlying CWE (for example, IDOR to CWE-639 and API1/A01). One finding may map to several categories; pick the controlling one.
3. **Locate the requirement.** Find the ASVS requirement(s) that the control must satisfy; the text becomes the acceptance criterion.
4. **Choose the fix.** Prefer a structural control (central authz, parameterized API) over a spot patch (one extra `if`).
5. **Add a test.** Every fix gets a regression test that fails on the old code; for authz, test the negative case across roles and tenants.
6. **Track to closure.** Owner, severity, SLA, and exception path; reopen automatically if the test regresses.
7. **Report upward.** Roll up by category and business unit; count open criticals and mean age, not raw finding volume.

| Finding source | Typical categories | Verification after fix |
|---|---|---|
| SAST | Injection, crypto misuse, hardcoded secrets | Unit/integration tests, re-scan |
| DAST | Authz gaps, misconfig, injection | Authenticated regression tests |
| SCA | Known-vulnerable dependencies | Rebuild and redeploy, reachability analysis |
| IaC scan | Cloud/K8s misconfig | Policy-as-code gates, drift detection |
| Pen test | Business logic, chained access | Abuse-case tests, control redesign |
| LLM red team | Injection, exfiltration, tool abuse | Adversarial eval suite, see `./08-llm-security.md` |

## Verification tooling

| Layer | Tools (examples) | Cadence |
|---|---|---|
| SAST | Semgrep, CodeQL, language linters | Every PR, diff-scoped plus nightly full |
| DAST | ZAP, Burp (automation), API fuzzers | Nightly against staging, on release |
| SCA/dependencies | OSV-based scanners, Dependabot, Renovate | Every PR, nightly, continuously on running artifacts |
| Secrets | gitleaks, trufflehog, provider scanning | Pre-commit, PR, continuous |
| IaC/K8s | Checkov, Trivy config, kube-linter, Kyverno | Every PR, admission time |
| LLM | garak, PyRIT, promptfoo-style evals | On model/prompt changes, scheduled |
| Manual | WSTG-based test cases, threat-model-driven abuse cases | Per release for high-risk changes |

Automation finds classes; humans find chains. Combine scanner gates with a threat-model-driven manual pass on the highest-risk flows.

## Anti-patterns

- Quoting "OWASP compliant" as a property; compliance is against ASVS-style verifiable requirements.
- Mapping every finding to A01 and calling the report complete.
- Running SAST at maximum noise and disabling the gate because of false positives instead of tuning rules.
- Treating the Top 10 as the test plan and skipping the threat model.
- Fixing the symptom (one endpoint) without the class-wide control (policy layer).
- Letting scanner findings sit in a separate tracker from engineering work.
- Applying the LLM list only to the model and not to tools, retrieval, and outputs.
- Assuming internal APIs need no authz or rate limits.

## Checklist

- [ ] Target ASVS level chosen per application and recorded.
- [ ] Chosen ASVS requirements mapped to tickets and tests.
- [ ] Top 10 categories reviewed against the current design, with owners for gaps.
- [ ] API endpoints checked against all ten API risks, including object- and property-level authz.
- [ ] LLM features checked against the LLM risks and reviewed with `./08-llm-security.md`.
- [ ] Finding-to-control pipeline defined with severity SLAs and exception process.
- [ ] SAST, DAST, SCA, secrets, and IaC scanning wired into CI with tuned gates.
- [ ] Regression tests exist for every fixed class of finding.
- [ ] Metrics report open criticals and mean age, not raw counts.
- [ ] Current OWASP edition and chapter sets verified upstream at review time.
