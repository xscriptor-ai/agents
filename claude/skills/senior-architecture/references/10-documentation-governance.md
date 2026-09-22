# Documentation and Governance

Docs-as-code, architecture reviews, tech radar, decision logs, and keeping documentation alive.

## Docs-as-Code

Documentation lives in the same repository and workflow as the code it describes: Markdown in
version control, reviewed in pull requests, built and published by CI.

Principles:

- Same review flow as code; changes to structure and docs ship in one pull request.
- Docs have owners and freshness expectations, like code has maintainers and tests.
- Diagrams are generated from text sources; rendered artifacts are build products, not
  committed images ([./02-c4-modeling.md](./02-c4-modeling.md)).
- Searchable, internally linkable, and available where developers already are (repo, docs site,
  editor, portal).
- No private wiki islands for decisions; if it matters, it lives in the repo.

Typical toolchain (pick one path per org; verify current versions upstream):

| Need | Common choices |
|---|---|
| Static site | MkDocs Material, Docusaurus, Antora, VitePress |
| Diagram rendering | Structurizr CLI, PlantUML, Mermaid, D2 in CI |
| ADR rendering | log4brains, adr-viewer, Backstage ADR plugin, custom MkDocs generator |
| Developer portal / catalog | Backstage-class portal with TechDocs and a software catalog |
| Linting | markdownlint, Vale, lychee/link checkers |
| Search | Site-native search or an external index for large doc sets |

## Document Types

Separate types by purpose; mixing them produces documents nobody can use. Diátaxis is a useful
frame.

| Type | Purpose | Architecture examples |
|---|---|---|
| Tutorial | Learning by doing | "Set up a new service from the template" |
| How-to | Solve a specific task | "Add an event to the outbox", "Run a projection rebuild" |
| Reference | Look up facts | Service catalog entry, API/schema docs, config keys |
| Explanation | Understand why | ADRs, context map, quality attribute analysis |

Architecture document set for a system:

| Artifact | Answers | Owner | Review cadence |
|---|---|---|---|
| ADR log | Why decisions were made | Decision owners | On each decision; audit yearly |
| C4 context/container diagrams | What the system is and how it is wired | System architect | Quarterly or on change |
| Context map | How domains relate | Domain leads | On boundary change |
| Quality attribute scenarios and SLOs | What "good" means | Product plus platform | Quarterly |
| Risk register | What could go wrong | Architecture owner | Monthly |
| Runbooks | How to operate and recover | Service team | On incident and quarterly |
| Service catalog entries | Owner, tier, dependencies, SLOs | Service team | On change, verified quarterly |
| arc42-style system doc (optional) | Full system description | System architect | On significant change |

arc42 remains a solid outline for a comprehensive system description (context, constraints,
solution strategy, building blocks, runtime, deployment, crosscutting concepts, decisions,
quality, risks). Link sections to the artifacts above rather than duplicating them.

## Architecture Reviews

Review early, small, and often; a review is a conversation with an artifact, not a gate.

| Review type | Trigger | Scope | Duration |
|---|---|---|---|
| Design review | Before building a significant capability | One design, against drivers and boundaries | 60 min |
| Decision review | ADR in `proposed` state | One decision, options and consequences | 30-45 min async or 30 min live |
| Pull-request review | Any change touching a boundary | Concrete diff and fitness rules | As needed |
| Post-incident architecture review | After a severe incident | Failure mode, not blame | 60 min |
| Periodic health review | Quarterly per system | Drift, debt, risks, SLOs | 90 min |
| Cross-team brown bag | Monthly | Share patterns and lessons | 45 min |

Lightweight design-review agenda:

1. Context and drivers (5 min) — which attributes, which constraints.
2. Proposed design (15 min) — C4 container plus the key flows, failure modes.
3. Tradeoffs and alternatives (15 min) — rejected options and why.
4. Boundary and data ownership check (10 min) — owners, single writer, dependencies.
5. Risks and decisions (10 min) — what ADRs are needed, what risks to register.
6. Actions and owners (5 min).

Roles: one facilitator (keeps time), one scribe (records decisions and actions), reviewers with
boundary expertise, and an accountable owner for the outcome. No status presentations, no
solutions designed in the meeting.

Review checklist:

- [ ] Drivers and ranked attributes stated, not implied.
- [ ] Current versus target state clearly separated.
- [ ] Data ownership and single-writer rules hold.
- [ ] Failure modes addressed: timeout, retry, partition, overload, data loss.
- [ ] Operational story: deploy, rollback, observe, on-call.
- [ ] Cost impact estimated.
- [ ] Security and compliance implications named.
- [ ] Decisions captured as ADRs; risks registered with owners.
- [ ] Actions have owners and dates; follow-up scheduled.

## Technology Radar

A radar communicates technology guidance without policy documents: what to adopt, trial, assess,
or hold.

Structure:

- **Quadrants** — techniques, tools, platforms, languages and frameworks.
- **Rings** — Adopt (proven, default), Trial (use in real projects with support), Assess (spike
  only), Hold (do not start new work).
- **Entries** — name, ring, one-line rationale, movement (new/moved in/out), owner.

| Quadrant | Entry example | Ring | Rationale |
|---|---|---|---|
| Techniques | Transactional outbox | Adopt | Required for reliable event publication |
| Techniques | Event sourcing | Trial | Strong audit value; steep learning curve |
| Tools | Structurizr DSL | Adopt | Model once, render many views |
| Platforms | Managed Kafka-compatible broker | Adopt | Operational burden removed; verify limits |
| Languages/frameworks | Serverless functions for glue | Trial | Great for spiky loads; watch cold starts |
| Tools | Hand-drawn architecture diagrams | Hold | Stale immediately; use diagrams-as-code |

Process:

1. Collect nominations from teams (with use evidence).
2. A small architecture group (or guild, not a gate) reviews and assigns rings.
3. Publish with dates and rationale; revisit quarterly; record ring moves.
4. Rings communicate guidance, not permission: teams may deviate with an ADR explaining why.
5. Never let the radar outlive its rationale; publish review dates and archive stale entries.

## Decision Logs

ADRs cover significant decisions. Everything else still needs a discoverable home:

- **Meeting decisions** — record decisions, actions, and owners in the meeting notes; promote any
  decision with lasting architectural impact into an ADR within the same week.
- **Small technical choices** — a "decisions" section in the relevant design doc or module
  README is enough; do not inflate them into ADRs.
- **Deviations** — a short ADR explaining the exception to a standard or radar "hold".
- **Deprecations** — announce with date, replacement, and a migration path; keep a deprecation
  page or ADR; track usage until zero.

Log hygiene: one searchable location per repo; dated entries; links between meetings, ADRs, PRs,
and incidents; no decision buried in a chat thread.

## Keeping Docs Alive

Doc rot is the default state; counter it with ownership and automation.

- **Owner per document or section**, recorded in front matter or the catalog.
- **Freshness SLA** — for example: runbooks quarterly, diagrams quarterly or on change, ADRs on
  change plus yearly audit, catalog entries verified quarterly.
- **Automated checks in CI**: markdown lint, Vale style, link checking (internal and external),
  Mermaid/PlantUML render, ADR index and status validation, diagram source changed alongside
  code when boundaries change.
- **Doc tests**: run the commands in how-tos in CI where feasible (template generation, seed
  scripts); at minimum, extract and compile code samples.
- **Review hooks**: pull requests that add a dependency, service, or integration require the
  catalog/diagram update in the same change (enforced by template or CI).
- **Archive policy**: move superseded docs to an `archive/` area with a date; delete what has no
  historical or legal value; keep ADRs forever, delete stale how-tos.
- **Findability**: consistent naming, one entry point (docs homepage or portal), search that
  covers ADRs and catalog.

Metrics that indicate health (use for trends, not targets to game):

| Metric | Healthy signal |
|---|---|
| % services with an owner and SLO in catalog | 100% |
| ADRs created per quarter and superseded correctly | Non-zero, current |
| Mean doc age for runbooks/diagrams | Within freshness SLA |
| Broken-link count in CI | Zero |
| Onboarding time to first production change | Falling |
| Post-incident actions closed on time | Rising |

## Anti-Patterns

- **Wiki graveyard** — docs in a separate tool that nobody updates; decisions live only in
  chat.
- **Screenshot diagrams** — committed PNGs with no source model; stale on first deploy.
- **Review as gate** — approval theater late in delivery; teams route around it.
- **Radar as policy** — using rings to forbid rather than advise; innovation dies at "Assess".
- **Docs for everything** — writing a design doc for a config change; signal drowns.
- **ADR inflation** — dozens of trivial ADRs; readers stop trusting the log.
- **Ownership vacuum** — no owner per doc, so freshness depends on goodwill.
- **Metrics as goals** — optimizing doc count or review count instead of decisions made and time
  to change.

## Checklist

- [ ] Docs live in the repo and ship with code changes.
- [ ] Each artifact has an owner and a freshness SLA.
- [ ] CI lints, link-checks, and renders diagrams and ADR indexes.
- [ ] Review types and cadences are defined; reviews are timeboxed with actions tracked.
- [ ] Decisions from reviews and meetings become ADRs when significant.
- [ ] Tech radar is published, dated, and reviewed quarterly; deviations use ADRs.
- [ ] Catalog is complete: owner, tier, dependencies, SLOs for every service.
- [ ] Archive policy exists; superseded docs are moved or deleted deliberately.
- [ ] Onboarding path uses the docs and is tested with new joiners.

## Related

- The decision records this governance keeps alive: [./01-adr.md](./01-adr.md)
- Diagrams as code and freshness: [./02-c4-modeling.md](./02-c4-modeling.md)
- Review inputs from quality attributes and risks: [./09-quality-attributes.md](./09-quality-attributes.md)
