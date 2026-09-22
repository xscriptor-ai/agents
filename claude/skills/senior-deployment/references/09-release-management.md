# Release Management

Scope: versioning schemes, changelogs, artifact provenance and signing, release trains versus continuous delivery, approval flows, communication, and post-release review.

## Versioning

| Scheme | Format | Use when | Notes |
|---|---|---|---|
| SemVer | MAJOR.MINOR.PATCH | Libraries, APIs, anything with compatibility promises | Breaking change means major; pre-1.0 still implies churn |
| CalVer | YYYY.MM or YYYY.WW | Products and continuously delivered services | Less about compatibility, more about recency |
| Build number / pipeline ID | Numeric | Internal services | Pair with commit SHA for traceability |
| Date plus counter | YYYY.MM.DD.N | Daily releases | Readable and orderable |
| Hash only | SHA prefix | Ephemeral artifacts | Poor human communication; acceptable as a secondary identifier |

Rules:

- One version per artifact, immutable. The same version is never rebuilt or republished; a fix gets a new version.
- Version the artifact and the release separately where useful: release = version plus environment plus deploy ID. See `./07-observability-rollback.md`.
- Tag in version control exactly what was built; the tag points at the commit, and CI records the digest it produced from it.
- Never reuse a version after rollback; the rolled-back version remains a historical fact.
- Pre-release identifiers (`-rc.1`, `-beta.2`) are for artifacts that must be distinguishable without claiming stability.
- For APIs and packages, document the compatibility policy: what constitutes a breaking change and the deprecation window. See the api-design pack if installed.

## Changelogs

Changelogs are for users; commit logs are for developers. Keep both and do not confuse them.

- Structure by release with date and version; group entries as Added, Changed, Fixed, Deprecated, Removed, Security.
- Write in terms of user-visible effects, not commit messages. "Reduce checkout latency" beats "refactor pricing service".
- Every release has changelog entries, including patch releases; "internal changes" is a valid entry when it is honest.
- Mark breaking changes prominently with the migration path.
- Link to the commit range or PRs for forensic use.
- Automate the skeleton from conventional commits or labels, and require human editing for user-facing clarity. Fully automated changelogs are noisy; fully manual changelogs rot.
- Keep a changelog file or release notes system in the repository as the source of truth; the release UI or announcement is derived from it.
- Publish per-release notes to the audience that consumes them: users, operators, or internal teams.
- Do not rewrite published changelog history; append corrections.

## Artifact Provenance

Provenance answers: who built this, from what source, with what inputs, and can it be verified?

| Element | Purpose |
|---|---|
| Immutable digest | Identity and integrity of the artifact |
| Signature | Authenticity of the producer |
| SBOM | Dependency and license inventory |
| Build attestation | Builder identity, source commit, parameters |
| Release ledger | Mapping of version to digest, environment, time, actor |
| Registry policy | Prevents overwrites and unsigned pushes |

Rules:

- Sign with a workload identity bound to the build system (keyless where supported) and verify at admission or before deploy. See `./02-ci.md`.
- Store the mapping `version -> digest -> commit` in a queryable ledger; reconciliation between tag and digest must be automatic.
- Registries should reject tag mutation after publish and require signatures for production namespaces where the platform supports it.
- Provenance attests to the build, not to behavior: passing provenance does not mean the code is correct. It answers supply-chain questions only.
- Retain artifacts for the rollback window and any compliance period; retention policy must outlive the longest plausible rollback.
- Verify provenance at deploy time; a warning that can be ignored will be ignored. Make verification blocking for production.

## Release Trains versus Continuous Delivery

| Model | Cadence | Merits | Costs |
|---|---|---|---|
| Continuous | On merge, gated automatically | Fast feedback, small batches, low risk per change | Requires strong tests, observability, rollback, and flags |
| Release train | Fixed schedule (daily, weekly) | Predictable, bundles approvals, easier coordination | Larger batches, pressure to include late changes, slower feedback |
| Windowed | Fixed maintenance windows | Regulatory fit, coordinated operations | Availability gaps, emergency processes dominate |
| Feature-flag releases | Continuously deployed, deliberately exposed | Decouples deployment from release | Flag governance is load-bearing |

- Choose based on risk tolerance, regulatory context, and team capability, not fashion. A team without observability will not succeed at continuous delivery by announcing it.
- If using a train, freeze the train contents at a cutoff; late changes wait for the next train or ride an explicit emergency path.
- Continuous delivery still benefits from a release cadence for user communication; deploy continuously, announce deliberately.
- Keep release size bounded in every model. Large batches make rollback and diagnosis harder.

## Approval Flows

Approval is a control, not a ritual. Design it to catch what automation cannot.

- Separate duties where required: the person who writes the change should not be the only approver for a production release in regulated contexts.
- Automated gates run first; human approval happens on top of green automated evidence, never instead of it.
- Approval scopes: PR review, environment promotion, emergency change. Keep them distinct; do not require a full change board for a two-line config fix.
- Emergency changes: a documented break-glass path with reduced ceremony, mandatory retrospective, and automatic follow-up. Speed comes from pre-authorized roles, not from skipping records.
- Record approvals with actor, scope, timestamp, and the artifact digest approved. An approval that names a branch rather than a digest is not an approval.
- Expiry: approvals for an artifact are invalidated when the artifact changes or after a defined window. Stale approvals accumulate risk.
- Keep the number of required approvers as low as the risk allows; high friction produces rubber stamps.

## Communication and Deprecation

- Announce user-visible changes before they land: what, when, impact, and the rollback or mitigation path.
- Maintenance windows for disruptive operations are scheduled, announced, and rehearsed; preference is always zero-downtime operation.
- Deprecations have a timeline: announce, warn in logs or headers, provide the replacement, and only then remove. See the api-design pack if installed.
- Status communication during incidents follows the incident process; release communication and incident communication should agree on facts already published.

## Post-Release Review

The review closes the loop and turns release practice into organizational learning.

Inputs:

- Did the release meet its SLOs and guardrails over the observation window? See `./07-observability-rollback.md`.
- Rollbacks, aborted rollouts, flags flipped back, and emergency changes.
- Deploy frequency, lead time for changes, change failure rate, and time to restore: track the four delivery metrics, with care not to gamify them.
- Incidents correlated with releases; whether the release process or the code was at fault.
- Flag and migration cleanup status created by this release. See `./08-feature-flags.md` and `./06-database-migrations.md`.

Outputs:

- Action items with owners, especially for rollbacks and near misses.
- Process changes with a test for whether they helped (for example, a new gate must have a false-positive story).
- Updates to runbooks and checklists used during the release.
- Feed the next release plan: batch size, cadence, and gate tuning.

Cadence: lightweight per release, deeper monthly or quarterly. Avoid turning every deploy into a meeting; sample and deepen where the metrics say risk is concentrated.

## Release Evidence and Audit

For regulated or high-trust contexts, assemble the evidence pack per release:

- Version, tag, commit, artifact digest, and SBOM.
- Signature and provenance attestation, plus the verification result at deploy.
- Approvers, approval scope, and timestamp bound to the digest.
- Migration list with compatibility classification and verification results (`./06-database-migrations.md`).
- Test and security scan results for the exact commit.
- Rollout plan, analysis results, and the final state (promoted or rolled back).
- Post-release metrics window and any follow-up actions.

Rules:

- Evidence is generated automatically as a byproduct of the pipeline; if assembling it takes a human afternoon, it will be wrong under deadline pressure.
- Store evidence immutably alongside the artifact or in a system with retention at least as long as the artifacts it describes.
- Audit asks "prove this version was tested and approved"; the answer must be a query, not a hunt through chat.

## Migration Notes

- Moving from manual releases to a release train: start with a fixed weekly cutoff, automate the evidence, and only then shorten the cadence.
- Moving from a train to continuous delivery: prerequisites are progressive delivery with automated gates, SLO-based rollback, and flag governance (`./03-cd-strategies.md`, `./07-observability-rollback.md`, `./08-feature-flags.md`).
- Moving from branch-based releases to artifact promotion: tag the built commit, publish the digest, and make environments consume the digest; delete the per-environment build jobs afterward.
- Moving from human-only approvals to automated gates: run gates in advisory mode first, measure false negatives against real incidents, then make them blocking.

## Anti-Patterns

- Rebuilding an artifact because the original pipeline is gone; version reuse after a rollback.
- Changelogs generated verbatim from commit messages with no user-facing editing.
- Signing images but never verifying signatures at deploy.
- Approvals on a branch name instead of an immutable digest.
- Trains that grow to a hundred changes and cannot be rolled back safely.
- Emergency changes with no retrospective and no follow-up.
- Provenance treated as a guarantee of correctness.
- Version numbers with no compatibility policy behind them.
- Release notes that omit breaking changes or migration steps.
- Post-release reviews that produce no owned actions.

## Checklist

- [ ] Versioning scheme documented with a compatibility policy.
- [ ] Versions immutable; tags point at the exact built commit; digests recorded.
- [ ] Changelog written for users, grouped and linked to the release.
- [ ] SBOM, signature, and build attestation produced and stored per release.
- [ ] Provenance verified in the deploy path, blocking for production.
- [ ] Release model chosen and batch sizes kept intentional.
- [ ] Approval flow scoped by risk; approvals name a digest and expire.
- [ ] Emergency path documented with retroactive review.
- [ ] Deprecations announced with a timeline and replacement.
- [ ] Post-release review with owned actions and delivery metrics tracked.
