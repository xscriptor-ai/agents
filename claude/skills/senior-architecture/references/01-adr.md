# Architecture Decision Records

Purpose, template, lifecycle, repository layout, review process, and superseding for ADRs.

## Why ADRs

An ADR captures one architecturally significant decision: the forces in play, the option chosen,
and the consequences accepted. It exists so that six months later a maintainer can answer "why is
this like this?" without archaeology in chat history, and so a reviewer can challenge the
reasoning rather than the code.

What ADRs buy:

- **Decision durability** — context survives team changes and reorgs.
- **Cheaper review** — the decision is reviewed once, before the expensive code exists.
- **Explicit tradeoffs** — rejected options are visible; "we always did it this way" stops.
- **Onboarding speed** — a chronological decision log is the fastest architecture history.
- **Audit trail** — regulated environments get a defensible record of design intent.

What ADRs do not do: document interfaces (that is OpenAPI/AsyncAPI/proto), describe current
structure (C4 diagrams), or replace design docs for large initiatives (link those instead).

## When to Write One

Write an ADR when a decision is expensive to reverse or constrains other teams. If reversing it
would take more than a sprint or require coordinated migration across services, it is significant.

| Write an ADR | Skip (put it in code review or a comment) |
|---|---|
| Choosing a style: monolith, microservices, serverless | Naming a class or endpoint |
| Datastore, message broker, or protocol choice | Library patch-level upgrades |
| Data ownership and single-writer boundaries | Internal refactoring behind a stable interface |
| Consistency model, saga, or outbox strategy | Test structure and fixtures |
| Authentication/authorization model, tenancy | Log formatting |
| Cross-team integration contract and versioning policy | Local code conventions already in a style guide |
| Buy vs build for a platform capability | Throwaway prototypes (write one if the prototype informs a keep/rewrite call) |
| Deliberate deviation from a standard or fitness rule | Following the standard |

Rules of thumb: one decision per ADR; if the title needs "and", split it. If you cannot state the
decision in two sentences, the decision is not ready. Timebox: a good ADR takes 30-90 minutes; a
week means the decision needs a design doc plus an ADR summary.

## Lifecycle

Statuses are state, not ceremony. The file is never deleted; it is superseded.

| Status | Meaning | Who sets it |
|---|---|---|
| `proposed` | Under review; do not build on it yet | Author |
| `accepted` | Decided and in force | Decision owner after review window |
| `rejected` | Considered and declined; keep for history | Decision owner |
| `deprecated` | No longer recommended but still in effect somewhere | Owner when guidance shifts |
| `superseded by ADR-NNN` | Replaced by a newer decision | Author of the new ADR |

Transition rules:

- `proposed` -> `accepted` requires a named decision owner and a review deadline; silence past
  the deadline counts as lazy consensus unless an objection was raised.
- `accepted` -> `superseded` requires an explicit link in both directions (new ADR links back,
  old ADR updated in place).
- Only `accepted` ADRs may be cited as constraints in reviews.
- An `accepted` ADR can be `amended` with a dated addendum if the change is editorial; if the
  decision itself changes, supersede.

## Template

Use MADR-style (Markdown Any Decision Records; MADR 3.x-4.x, verify upstream). Keep it to one
screen where possible.

```markdown
# ADR-0007: Use transactional outbox for order events

- Status: accepted
- Date: 2026-03-11
- Deciders: platform team, orders team
- Supersedes: none
- Superseded by: none

## Context and Problem Statement

Order state changes must reach billing and fulfillment without dual writes.
Dual writes to the database and broker already caused two lost-update incidents.

## Decision Drivers

- No lost events on crash between commit and publish
- At-least-once delivery acceptable; consumers already deduplicate by event id
- Delivery latency under 5 seconds p99

## Considered Options

1. Dual write to DB and broker
2. Transactional outbox with a relay
3. Change data capture (CDC) directly on the orders table

## Decision Outcome

Chosen: **transactional outbox with a relay**, because it keeps the transaction local
and the publish path observable without schema-level coupling to a CDC topology.
CDC remains an option if outbox relay lag becomes a bottleneck.

### Consequences

- Good: no lost events, replayable, testable without a broker
- Bad: relay is another component to run and monitor
- Bad: events are published after commit, so read-after-write consumers see lag

### Confirmation

Alert when outbox lag p99 exceeds 5 seconds or dead-letter count grows.
```

Minimal acceptable version: Title, Status, Date, Context, Decision, Consequences, and links to
the design doc. Extra sections (drivers, options, confirmation) earn their space by making the
decision reviewable.

## Repository Layout

Keep ADRs with the code they constrain. For a monorepo, use one root log plus optional
subsystem logs; for many repos, keep a central index that links to repo-local ADRs.

```
docs/
  adr/
    README.md              # index table + how to add one
    0001-record-architecture-decisions.md
    0002-modular-monolith-first.md
    0003-postgres-as-primary-store.md
    0007-transactional-outbox-for-order-events.md
    template.md            # copied for each new ADR
```

Conventions:

- Zero-padded, monotonically increasing four-digit numbers; never reuse a number.
- Filename `NNNN-kebab-case-title.md`; title line inside repeats `ADR-NNNN: Title`.
- The index `README.md` lists number, title, status, date, and links. CI fails if a file is not
  indexed or a status link is broken.
- For a large initiative with many related decisions, group them in `docs/adr/<initiative>/`
  but keep global numbering.
- The very first ADR is usually "ADR-0001: Record architecture decisions" — it documents this
  process itself.

## Superseding Decisions

Superseding is how architecture evolves without losing history.

1. Draft the new ADR with `Status: proposed` and a `Supersedes: ADR-0007` field.
2. In the old file, change the status to `superseded by ADR-0012` and add a one-line pointer.
3. Apply the same change in the index table in the same pull request.
4. In the new ADR's Context, summarize what changed since the old decision (new constraints,
   cost, scale, incident) rather than re-arguing from scratch.
5. Mark the migration work in the new ADR's Consequences and link the migration plan (see
   [./08-migration-evolution.md](./08-migration-evolution.md)).

Do not edit accepted decisions to match present reality. That erases the reasoning that made
them right at the time.

## Review Process

Async-first, timeboxed, with a named owner accountable for the outcome.

| Step | Actor | Output |
|---|---|---|
| 1. Draft | Author | ADR in `proposed`, posted as a pull request |
| 2. Socialize | Author | Reviewers: affected teams, boundary owners, on-call for impacted systems |
| 3. Review window | Reviewers | Comments resolved or raised as objections, typically 3-5 working days |
| 4. Decide | Decision owner | `accepted` or `rejected`, with rationale recorded |
| 5. Publish | Author | Merge, index update, announce in the architecture channel |
| 6. Enforce | Code owners | Fitness functions, linters, or review checklists encode the decision |

Process rules:

- One accountable decider per ADR; "everyone agrees" is not an owner.
- Dissent is recorded, not buried: add an "Objections and resolutions" subsection when views
  diverge.
- Urgent decisions use an expedited window (24 hours) with a follow-up review scheduled.
- A decision with cross-team blast radius gets at least one reviewer from each affected team.
- Reviewers check for: stated quality attributes, rejected alternatives, reversibility, and
  consequences for operations.

## Tooling and Automation

- `adr-tools` and similar CLIs scaffold and number files; `log4brains` and Backstage plugins
  render searchable ADR sites from the same Markdown.
- CI checks worth having: index completeness, valid status values, no duplicate numbers, links
  resolve, superseded pairs are bidirectionally linked, and changed ADRs do not silently flip
  `accepted` to `proposed`.
- Link the ADR from the pull request that implements it ("Implements ADR-0007") and from code
  where the decision is easy to violate (a comment at the boundary, not a spray of links).
- Tool versions move; verify current releases upstream rather than pinning from this document.

## Anti-Patterns

- **Retroactive ADR** — writing "the decision" after shipping to justify it; reviewers cannot
  influence what already merged.
- **Omnibus ADR** — one file covering half the system; nobody can supersede a subset.
- **Status drift** — old ADRs left `accepted` forever while the code moved on; readers lose
  trust in the log.
- **Template theater** — filling every section with boilerplate; an honest short ADR beats a
  padded one.
- **No rejected options** — a decision without alternatives is an announcement, not a decision.
- **ADR as design doc** — narrative designs in the ADR hide the single decision; link a design
  doc instead.
- **Orphan log** — ADRs in a wiki nobody reads; keep them in the repo and reference them in
  reviews.

## Checklist

- [ ] One significant, hard-to-reverse decision per ADR.
- [ ] Status, date, decider, and supersession links accurate.
- [ ] Context names the forces and at least one rejected alternative.
- [ ] Decision is a complete sentence: subject, verb, rationale.
- [ ] Consequences list both benefits and costs, including operational burden.
- [ ] Index updated; links resolve; numbering unique.
- [ ] Affected boundary owners reviewed it.
- [ ] Implementation PR links the ADR; enforcement (if any) is in CI.
- [ ] Superseding updates both files in one pull request.

## Related

- Diagrams that show the resulting structure: [./02-c4-modeling.md](./02-c4-modeling.md)
- Migration planning for decisions that replace a system: [./08-migration-evolution.md](./08-migration-evolution.md)
- Reviews, tech radar, and keeping the log alive: [./10-documentation-governance.md](./10-documentation-governance.md)
