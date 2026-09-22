# Incident Response

> Scope: security incident handling — detection and triage, containment, forensics, communication, postmortems, tabletops, and metrics.

## Lifecycle

Align with NIST SP 800-61r3 (which maps response activities onto the CSF 2.0 functions, Govern, Identify, Protect, Detect, Respond, Recover — verify the current revision upstream) or your regulator's framework. The phases are not strictly sequential; containment and analysis overlap.

1. **Prepare** — playbooks, access, tooling, contacts, backups, and rehearsals. Everything else is improvisation without this.
2. **Detect and analyze** — validate the signal, scope it, classify severity, start the record.
3. **Contain** — stop the spread while preserving evidence; eradicate the root cause.
4. **Recover** — restore service from known-good state and watch for recurrence.
5. **Learn** — blameless postmortem, action items, updated playbooks and controls.

## Severity classification

Define severity before the incident, not during it. A workable four-level scheme:

| Severity | Definition | Examples | Targets |
|---|---|---|---|
| SEV1 / critical | Confirmed breach, active data exfiltration, or safety impact; major customer or regulatory exposure | Ransomware, production data theft, compromise of signing keys or cloud root | Immediate page, incident commander and exec notified within minutes, updates every 30-60 min |
| SEV2 / high | Confirmed compromise limited in scope, or active exploitation with partial controls holding | Compromised service account, malware on one host, exposed credential with access | Page on-call, updates hourly, containment within hours |
| SEV3 / medium | Suspicious activity needing investigation, or a vulnerability with a credible path | Anomalous admin action, unpatched critical on an exposed host | Ticket with an owner, response within a business day |
| SEV4 / low | Policy violation, scanner finding without evidence of exploitation | Misconfiguration without exposure, phishing email reported by one user | Normal backlog with SLA |

Decision rule: when unsure between levels, start one higher and downgrade with evidence. Also define severity escalation triggers explicitly: any confirmed data access, any privileged credential compromise, any detection of lateral movement.

## Detection and triage

Detection sources: SIEM correlation, EDR/runtime alerts, cloud audit logs, identity provider anomaly detection, WAF and gateway alerts, secret scanning, supply-chain advisories, customer reports, and employee reports. Fill gaps where a critical path has no signal (for example, no audit logging on the data plane).

Triage checklist for every alert:

1. **Validate** — is this real, and is it happening now? Reproduce the signal, not the assumption.
2. **Scope** — which identities, hosts, accounts, and data are involved? Pull the last 90 days of relevant history, not the last hour.
3. **Determine initial access** — how did the actor get in and when? Check identity logs, exposed services, recent changes, and known vulnerable components.
4. **Check persistence** — new credentials, tokens, scheduled jobs, webhooks, CI secrets, OAuth grants, SSH keys, and cloud roles.
5. **Assess data impact** — what could have been read or exfiltrated? Classification and volume matter for notification.
6. **Classify severity and open the record** — single source of truth with timestamps in UTC.
7. **Page the right people** — incident commander, comms, legal, and domain owners per severity.

Alert quality matters more than alert volume: tune to high-fidelity signals, enrich with asset and identity context, and track false-positive rates. A noisy SIEM that everyone ignores is an outage of detection.

## Containment

Containment choices trade speed against evidence preservation and availability. Decide with the incident commander, and record the reason for each action.

| Action | Use when | Risk |
|---|---|---|
| Revoke sessions and rotate credentials | Credential compromise suspected | Attacker may notice; legitimate users disrupted |
| Disable an identity or service account | Actor uses a specific identity | May break automations; preserve logs first |
| Isolate a workload/host from the network | Active lateral movement or runtime malware | Memory-resident evidence may be lost; capture before isolating if possible |
| Block egress destination or domain | Exfiltration in progress | Attacker rotates infrastructure; keep logging exits |
| Roll back to known-good artifact/config | Compromised deploy or dependency | Rollback may reintroduce the vulnerable version; patch forward first |
| Disable a feature or tool | Injection or abuse through a specific path | Product impact; needs a re-enable plan |
| Rotate keys/signing identities | Key compromise | Wide blast radius; requires a rotation runbook |

Order of operations: preserve the highest-volatility evidence first (memory and running state), then contain. When speed is essential to stop data loss, contain first and accept partial evidence; document the tradeoff.

Containment is not eradication: re-imaging without finding initial access and persistence guarantees a second incident.

## Forensics and evidence

- **Order of volatility**: CPU/registers, memory, network connections, running processes, disk, remote logs, backups.
- Capture memory and disk images with tested tooling before rebooting; hash every image at collection (`sha256sum`) and record collector, time, and location.
- Cloud forensics: enable and export audit trails (management, data, and identity logs), snapshot disks and memory where supported, and preserve container images by digest. Logs with short retention must be exported early.
- Containers and Kubernetes: capture pod spec, image digest, environment references, service account, and node logs; treat the node as compromised if privileged access occurred.
- Build a timeline in UTC from all sources; keep a chain-of-custody record for anything that may reach legal or regulatory review.
- Engage legal early for privilege and notification duties; do not let the security team silently make legal calls.
- Avoid "cleaning up while investigating": every command changes state. Log your own actions.

## Communication

Roles to fill (one person may hold several in small teams): incident commander, deputy/scribe, communications lead, legal/compliance, executive sponsor, and domain leads.

| Audience | Cadence | Content |
|---|---|---|
| Incident team | Continuous in a dedicated channel | Facts, hypotheses labeled as such, decisions, tasking |
| Leadership | Per severity policy (30-60 min for SEV1) | Impact, status, next update time, decisions needed |
| Customer-facing teams | Before public statements | Approved language, FAQ, escalation path |
| Customers/partners | Per legal and contractual duties | Validated facts, remediation, contacts; no speculation |
| Regulators | Regulator-specific clocks | See below |
| Employees | After customer notification | What happened, what to say, where to route questions |

Regulatory clocks to know and verify with counsel (all are jurisdiction- and sector-specific; confirm the current requirements upstream):

- **GDPR**: personal data breach notification to the supervisory authority within 72 hours of awareness where required; data subjects without undue delay when high risk.
- **SEC** (US public companies): material cybersecurity incident disclosure generally within four business days of determining materiality.
- **DORA** (EU financial entities): major incident reporting with very short initial notification deadlines (hours), intermediate and final reports following.
- **EU Cyber Resilience Act**: manufacturers report actively exploited vulnerabilities and severe incidents to the designated CSIRT on short clocks (an early-warning stage around 24 hours and follow-ups within days, phasing in from late 2026 — verify dates upstream).
- Sector rules (health, energy, telecom) add their own clocks; pre-map them per jurisdiction.

Practice the clocks in tabletop exercises; discovering the notification duty during a real incident is too late. Prepare holding statements and notification templates in advance, and route all external communication through legal and comms.

## Eradication and recovery

- Identify and remove root cause and every persistence mechanism; assume the actor left more than one.
- Rebuild from trusted sources rather than patching a compromised system: new credentials, re-imaged hosts, redeployed artifacts from verified digests.
- Rotate everything the actor could have touched: passwords, tokens, API keys, certificates, and cloud roles; invalidate sessions.
- Restore data from backups verified clean (attacker may have compromised backups); confirm integrity before returning to service.
- Return to production in stages with heightened monitoring; define explicit exit criteria and a rollback path.
- Watch for re-entry for a defined period after recovery; track it in the incident record.

## Postmortem

Blameless and factual. The goal is system change, not blame. Do it within days while memory is fresh.

Structure:

1. Summary, severity, customer and data impact, duration.
2. Timeline in UTC with detection, decision, and action points, including what took so long.
3. Root cause and contributing factors (technical, process, organizational); use causal trees or "five whys" without stopping at "human error".
4. What worked and what did not, including detection quality and tooling gaps.
5. Action items: specific, owned, dated, and tracked in the normal backlog; include control and detection improvements.
6. Appendix: evidence references and regulatory notifications made.

Publication practice: share broadly (redacted where needed). An unpublished postmortem teaches one team; a published one teaches the company.

## Tabletop exercises

- Scenario types: ransomware, cloud credential theft, supply-chain compromise, insider data theft, LLM exfiltration, lost device, regulatory notification race.
- Cadence: at least quarterly for the security team, twice yearly for engineering leadership; rotate scenario types.
- Participants: on-call, engineering, comms, legal, and an executive sponsor; include a scribe and an evaluator.
- Inject new facts every 15-20 minutes ("backups are also encrypted", "the regulator just called") to force decisions.
- Test the boring parts: contact tree, out-of-band communication, evidence access, and who can approve emergency changes.
- Output: findings and action items tracked like postmortem actions; re-run scenarios that expose gaps.

## Metrics

| Metric | Definition | Use |
|---|---|---|
| MTTD | Mean time to detect from first activity | Measures detection investment |
| MTTA | Mean time to acknowledge | Measures on-call responsiveness |
| MTTC | Mean time to contain | Measures playbook effectiveness |
| MTTR | Mean time to recover service | Pairs with MTTC; watch for improvement gaming |
| Internal detection rate | Incidents found internally vs externally reported | The single best health signal; aim for high internal rate |
| Escape rate | Incidents caused by changes that passed review/scanning | Ties response back to prevention |
| Action-item completion | Postmortem items closed by the due date | The difference between learning and theater |
| Reopen rate | Incidents that recur within a window | Whether root cause was really addressed |

Track trends and outliers, not absolute values, and review metrics with engineering leadership. A metric used for individual performance stops being honest.

## Playbook starter list

- Credential compromise (user, service account, cloud key).
- Ransomware/malware on a host or cluster.
- Data exfiltration via application or database.
- Public data exposure (bucket, database, repository).
- Lost or stolen device with corporate access.
- Supply-chain compromise (dependency, CI, artifact).
- LLM/agent abuse or exfiltration (see `./08-llm-security.md`).
- Insider misuse and access revocation.
- Denial of service and resource exhaustion.

Each playbook: trigger, severity mapping, first 30 minutes, containment options, evidence to preserve, communication tree, recovery steps, and exit criteria. Test them in tabletops; keep them short enough to follow at 3 a.m.

## Anti-patterns

- No written severity definitions; every incident becomes a debate.
- Containment that destroys the evidence needed to find the entry point.
- Fixing the symptom and closing the incident without root cause.
- Postmortems that blame individuals and drive future incidents underground.
- Action items with no owner or date; they never get done.
- Regulatory notification discovered after the deadline.
- Channels outside the incident record (DMs), so the timeline is lost.
- Backups untested against ransomware; restore drills skipped.
- Metrics tracked but never reviewed with engineering leadership.
- Tabletops that never touch communication, legal, or executive decision-making.

## Checklist

- [ ] Severity matrix published with escalation triggers and response targets.
- [ ] On-call rota, paging, and out-of-band communication tested.
- [ ] Playbooks for the top scenarios exist, are current, and are exercised.
- [ ] Logging and retention cover identity, control plane, data plane, and network.
- [ ] Evidence collection tooling and custody procedures documented and tested.
- [ ] Legal and regulatory notification matrix maintained per jurisdiction.
- [ ] Communication templates and approval chains pre-drafted.
- [ ] Recovery uses verified backups and trusted rebuilds; exit criteria defined.
- [ ] Blameless postmortems within days; actions owned, dated, and tracked.
- [ ] Tabletop cadence scheduled with executive participation.
- [ ] Detection and response metrics reviewed regularly with leadership.
