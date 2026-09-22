# Threat Modeling

> Scope: design-time identification and prioritization of threats — data-flow modeling, STRIDE, attack trees, LINDDUN privacy analysis, risk scoring, and integration into delivery.

## Why and when

Threat modeling finds design flaws that scanners cannot: broken trust assumptions, missing authorization, and abuse paths. Do it when a system is new, when a trust boundary moves, when a new data class or actor (including an AI agent) appears, and when a significant dependency or deployment model changes. One focused session beats a document nobody reads.

The four questions every method answers:

1. What are we building?
2. What can go wrong?
3. What are we going to do about it?
4. Did we do a good enough job?

## Choosing a method

| Method | Best for | Cost | Output |
|---|---|---|---|
| STRIDE | Fast per-element analysis of a design | Low | Threat list mapped to mitigations |
| Attack trees | One high-value asset or goal, depth over breadth | Medium | Structured attack paths and costs |
| LINDDUN | Privacy and personal data (GDPR-style review) | Medium | Privacy threats and controls |
| PASTA | Risk-centric, business-objective-driven, regulated systems | High | Stage-by-stage risk analysis |
| OCTAVE | Organizational risk, not a single system | High | Practice-level risk profile |
| Abuse cases | Requirement-stage, agile teams | Low | Negative requirements and tests |

Pick one primary method and one secondary. Most product work runs STRIDE plus LINDDUN; a high-value asset (signing key, payment flow) gets an attack tree.

## Data-flow threat modeling

Model four element types and mark every place data crosses an identity, network, or privilege boundary.

| DFD element | Meaning | STRIDE focus |
|---|---|---|
| External entity | Actor or system outside your control | Spoofing, repudiation |
| Process | Code that handles data | All six |
| Data store | Persistence (DB, bucket, queue, vector index) | Tampering, information disclosure, repudiation |
| Data flow | Data in transit between elements | Tampering, information disclosure, denial of service |

Trust boundaries are the lines between different levels of control: user to edge, edge to service, service to database, service to third party, workload to LLM provider, agent to tool. Threats concentrate on boundaries; controls belong there too.

Practical steps:

1. Draw the current and next-state diagrams at the same level of abstraction; label protocols and data classes on every flow.
2. Mark trust boundaries explicitly, including inside the cluster (namespaces, service mesh, policy domains).
3. Enumerate threats per element with STRIDE; for each, record the abuse path, existing control, gap, and owner.
4. Turn mitigations into requirements and tests; every threat without a control becomes a backlog item or a written exception.
5. Revisit the model at each significant change, not annually.

## STRIDE per element

| Threat | Question | Typical controls |
|---|---|---|
| Spoofing | Can an actor pretend to be another? | Strong authn, mTLS, workload identity, signed tokens |
| Tampering | Can data or code be modified in transit or at rest? | Integrity checks, AEAD, signed artifacts, immutable stores |
| Repudiation | Can an action be denied? | Audit logs, time-stamped events, non-repudiable signatures |
| Information disclosure | Can data leak? | Classification, encryption, least privilege, redaction |
| Denial of service | Can availability be degraded? | Rate limits, quotas, timeouts, autoscaling, backpressure |
| Elevation of privilege | Can a principal gain rights it should not have? | Central authz, least privilege, sandboxing, no ambient authority |

Element matrix (use as a worksheet):

| Element | S | T | R | I | D | E |
|---|---|---|---|---|---|---|
| External entity | x | | x | | | |
| Process | x | x | x | x | x | x |
| Data store | | x | x | x | x | |
| Data flow | | x | | x | x | |

For each `x`, write one sentence: "A malicious X can Y, leading to Z." That is a threat statement; if you cannot write it, the threat does not apply.

## Attack trees

Attack trees decompose a goal into alternative and sequential steps. Use them for a single asset: "forge a signing key", "exfiltrate the customer database", "move funds without detection".

- Root: attacker goal, stated as an outcome.
- Children: `OR` nodes for alternatives, `AND` nodes for required steps.
- Leaves: atomic actions with a cost, skill level, and detection risk.
- Prune branches that existing controls make infeasible; annotate the cheapest surviving path.
- The cheapest path is the priority, not the longest one.

Example (password reset takeover):

```
Goal: take over a victim account
OR
  - Reset token theft
    AND - obtain token (referrer leak, log, shared mailbox)
    AND - use before expiry/rotation
  - Reset flow logic bypass
    AND - discover host header / IDOR weakness
    AND - trigger reset for victim
  - SMS OTP interception
    AND - SIM swap or SS7 access
  - Help-desk social engineering
    AND - impersonate victim convincingly
```

Controls fall out directly: bind tokens to the request, single use, short TTL, ignore Host headers for link generation, prefer passkeys for recovery, log and rate-limit reset, train help desk with challenge questions that are not public data.

## LINDDUN and privacy

LINDDUN drives privacy threats from data flows. Run it for anything processing personal data or behavioral telemetry.

| Letter | Threat | Question | Controls |
|---|---|---|---|
| L | Linking | Can data about a person be linked across contexts? | Pseudonyms, purpose separation, unlinkable identifiers |
| I | Identifying | Can a person be identified from data? | Anonymization, k-anonymity/differential privacy, minimize identifiers |
| N | Non-repudiation | Can a person be forced to own an action? | Deniable schemes where appropriate; careful audit scope |
| D | Detectability | Can presence or behavior be inferred? | Padding, batching, no side-channel timing |
| D | Disclosure | Can personal data be exposed? | Access control, encryption, minimization, retention limits |
| U | Unawareness | Are users unaware of processing? | Notice, consent, transparency, data-subject access |
| N | Non-compliance | Does processing violate law or policy? | Data mapping, retention schedules, DPIAs, deletion paths |

Privacy engineering rules: minimize collection, separate purposes, keep retention short and enforced by code, make deletion a tested path, and treat embeddings and telemetry as personal data when they can be re-identified.

## Risk scoring

Scoring exists to order work, not to be precise. Pick one primary scale and stay consistent.

| Tool | Use | Notes |
|---|---|---|
| CVSS 4.0 | Vulnerabilities with a known technical impact | Base score for triage; threat/environmental metrics only with data |
| EPSS | Likelihood a vulnerability is exploited in the wild | Good tie-breaker; low EPSS never excuses a critical on an exposed asset |
| SSVC | Decision-oriented triage (track, track*, attend, act) | Maps exploit status and exposure to action; favored by product security teams |
| OWASP Risk Rating | Application findings without a CVE | Likelihood and impact factors, useful for bug-bounty triage |
| DREAD | Legacy | Deprecated in most programs; avoid for new work |

Combine signals rather than trusting one: exploitability (EPSS, public exploit), exposure (internet, auth required), asset value (data class, blast radius), and detectability. A useful default policy:

- **Act now**: internet-exposed, exploitable, high asset value, or active exploitation.
- **Next cycle**: exploitable but not exposed, or exposed with strong compensating controls.
- **Track**: theoretical, high attack cost, or no path from the entry point.
- **Accept**: documented, owned, with expiry and a monitoring signal.

## Integrating at design time

- Add a threat-model gate to the design review: no model, no approval for boundary-changing work.
- Keep the model as code where possible (Threagile, pytm-style DSLs, Threat Dragon files) so it diffs and reviews like the rest of the repo.
- Export mitigations into the same tracker as functional requirements; label them with the threat id.
- Write abuse cases next to user stories: "as an attacker, I want to replay the webhook so that I can double-credit the account." Each abuse case gets a test.
- Reuse known threat libraries: MITRE ATT&CK for adversary behavior, CAPEC for attack patterns, CWE for weakness classes, cloud provider threat matrices for platform-specific paths.
- Record decisions and accepted risks as ADRs with owner and expiry; an accepted risk with no expiry is an unowned risk.

## Anti-patterns

- Threat modeling once, in a wiki, never updated; the next diagram is drawn by an attacker.
- Listing generic threats ("SQL injection") without the specific abuse path through this system.
- Modeling only the happy path and ignoring operational interfaces: admin panels, webhooks, imports, backups, CI.
- Treating the model as a checklist for the security team instead of the design team.
- Scoring every threat with a heavy framework so the exercise never finishes.
- Ignoring privacy because "we are B2B"; B2B data is still personal data.
- Forgetting the AI surface: prompts, retrieval corpora, tool calls, and model providers are new data flows and trust boundaries (see `./08-llm-security.md`).
- Mitigations that live only in the document and never become code, tests, or backlog items.

## Checklist

- [ ] Diagram covers users, services, data stores, queues, third parties, admin paths, and AI components.
- [ ] Every trust boundary is labeled with protocol and data classification.
- [ ] STRIDE applied per element; each threat has a written abuse path.
- [ ] LINDDUN applied where personal data or telemetry is processed.
- [ ] High-value assets have attack trees; cheapest path addressed.
- [ ] Each threat maps to a control, requirement, test, or owned exception with expiry.
- [ ] Scoring method chosen and applied consistently; exposure and exploitability considered.
- [ ] Model stored in version control and reviewed on boundary changes.
- [ ] Abuse cases added to the test suite.
- [ ] Follow-up session scheduled for the next significant change.
