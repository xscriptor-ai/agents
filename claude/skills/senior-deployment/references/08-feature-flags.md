# Feature Flags

Scope: flag categories and lifetimes, targeting and progressive exposure, evaluation architecture, lifecycle governance and cleanup, and testing flagged code.

## Flag Categories

| Category | Purpose | Lifetime | Owner | Default when provider fails |
|---|---|---|---|---|
| Release | Hide incomplete or risky functionality during rollout | Days to weeks | Delivery team | Off |
| Ops / kill switch | Disable a feature or dependency under stress | Permanent, exercised periodically | On-call | Fail-safe for the system, not for the feature |
| Experiment | Compare variants on a metric | Weeks (duration of the experiment) | Product plus data | Control variant |
| Permission / entitlement | Gate by plan, role, or contract | Long-lived | Product or billing | Plan-appropriate |
| Ops tuning (migration/backfill control) | Slow or pause background work | Weeks | Data or platform team | Safe path |

- Classify every flag at creation. The category determines its lifetime, test requirements, and cleanup process.
- Release flags are temporary scaffolding. Kill switches and entitlements are configuration and are governed like code.
- Different categories belong in different namespaces or providers where possible; mixing them makes cleanup ambiguous.

## Targeting and Progressive Exposure

Targeting dimensions:

- User or tenant ID (sticky bucketing), account attributes (plan, region), device or app version, and time window.
- Segments defined by stable attributes; avoid segments based on volatile behavior that changes mid-session.
- Percentage rollout: bucketing must be deterministic and sticky so a user does not flip variants between requests. Hash on the flag key plus a stable identifier.
- Ring-based exposure: internal users, then employees or dogfood tenants, then 1 percent, then 5, 25, 50, 100. Pause between rings and inspect metrics (`./07-observability-rollback.md`).
- Combined with canary: flags change behavior per cohort; canary changes which artifact serves traffic. They are complementary; do not use one to simulate the other (`./03-cd-strategies.md`).

Exposure design:

- Start with an allowlist of internal accounts; then named customers; then percentage; then general availability.
- Define the metric and the guardrail metrics before exposing: success metric, error rate, latency, and business guardrails.
- Predefine rollback criteria as numeric thresholds; "watch for a while" is not a criterion.
- Keep the rollout schedule in the flag system's audit trail, not only in a ticket.
- Consider dependencies between flags: killing flag A while flag B depends on it can leave a broken state. Document relationships.

## Evaluation Architecture

| Pattern | Latency | Freshness | Complexity | Use when |
|---|---|---|---|---|
| Local SDK evaluation with streamed rules | Microseconds | Near-real-time updates | Provider coupling, SDK in every service | Default for performance-sensitive services |
| Remote API evaluation per request | Network round trip | Instant | Availability dependency on the provider | Admin tools, low-QPS paths |
| Server-side evaluation proxy | Low | Near-real-time | Extra component | Central policy and caching |
| Edge/CDN evaluation | Very low | Near-real-time | Edge compute support | Frontend and edge routing |
| Config baked at deploy | Zero | Deploy cycle | Simple, no provider | Slower cadence, fewer flags |

Rules:

- Flag evaluation should be local and fast for request paths; a network call per request couples availability to the flag provider.
- Bootstrap state: the SDK must start with a sensible snapshot (or defaults) when the provider is unreachable at startup.
- Provider outage behavior is per-flag policy, not a global default. A kill switch should fail closed for the feature (disabled) while a core feature should fail open (enabled) to preserve availability. Decide and document per flag.
- Cache rules with a TTL and refresh on stream updates; handle flapping.
- Never put secrets in flag values; flag rules are widely readable.
- Frontend flags: do not leak unreleased features as disabled-but-shipped code paths with discoverable payloads; server-gate sensitive functionality and treat client flags as UX toggles only.
- Track flag evaluation events if the provider supports it, for audit and for identifying unused flags.

## Lifecycle Governance

Every flag has a lifecycle:

| Stage | Exit criterion | Gate |
|---|---|---|
| Proposed | Category, owner, expiry, and default defined | Flag review or template enforced |
| Created | Flag exists in all environments with safe defaults | Default off in production unless justified |
| Rolling out | Exposure plan executed with metrics | Guardrails green at each step |
| Fully on | Flag permanently on in production | Cleanup ticket issued with a deadline |
| Cleanup | Flag and dead code removed; evaluation removed | PR merged and flag archived |

Governance rules:

- Mandatory metadata: owner, category, creation date, expiry date, and a cleanup ticket. A creation form without these fields is rejected in the flag system or in review.
- Flag debt is tracked like dependency debt: a dashboard of flags past expiry, flags older than a threshold, flags with zero evaluations, and flags with a single state in production.
- Stale flags are removed on a schedule, owned by teams, with exceptions requiring justification.
- Removing a flag means removing the old branch of code, not just flipping it permanently on. Dead code behind an always-true flag is still dead code.
- Kill switches are the exception: they are reviewed periodically (tested in a game day), not removed. A kill switch that has never been exercised does not work.
- Entitlement flags are configuration; changes go through the same review and audit as pricing or permissions changes.
- Bulk operations (enable for all tenants) require the same care as a deploy: announce, measure, and keep a rollback path.

## Testing with Flags

Flags multiply states; naive testing explodes.

Strategies:

- Test each branch as its own behavior: unit tests for on and off paths, not a full combinatorial matrix.
- Keep flag branches shallow and short-lived. Deep flag nesting is a signal to refactor.
- Provide a test configuration that sets explicit flag values per test; never depend on the live provider in tests.
- Integration tests should run critical journeys with the flags in their production-default state, plus targeted runs for flags being rolled out.
- Do not let flag evaluation make tests non-deterministic: inject an evaluator or use an in-memory provider.
- Test the default path: the behavior when the provider is unavailable and defaults apply. This path runs during incidents, so it must be correct.
- For frontend flags, test both visual states where the change is meaningful; snapshot the differences intentionally.
- Contract tests for the flag payload: if the SDK or rule schema changes, tests catch it before production.
- Add a test that fails when a flag reference has no matching definition, catching typos that would otherwise silently default.

## Build versus Buy

| Option | Strengths | Costs | Use when |
|---|---|---|---|
| Hosted provider | Streaming updates, targeting UI, experiments, audit trail | Cost per seat or evaluation, vendor dependency, data egress | Product experiments and many flags |
| Open-source self-hosted | Control, no per-seat cost, data stays in-house | You run the control plane and upgrades | Platform teams with strong operations |
| Home-grown in config service | No new vendor; fits an existing config system | Targeting, streaming, audit, and experiments become your job | A small, stable number of flags |
| Build-time/environment config | Zero runtime dependency | No dynamic rollout; change needs deploy | Few, coarse toggles only |

- Whatever the choice, keep an abstraction layer thin but present: flag keys and evaluation calls behind a small interface so a provider swap is a contained change. The observability pack's signal-abstraction reasoning applies here too.
- Do not let provider SDKs spread through the codebase; evaluation belongs in service entry points, not in domain logic.
- Budget the provider cost against the value of experiments; a provider bill larger than the experiment program is a signal to consolidate.

## Operational Metrics for Flags

- Track evaluations per flag per version to prove rollout progress and to find unused flags.
- Track error and latency metrics split by flag variant for the flags under active rollout; variant-blind dashboards hide regressions. See `./07-observability-rollback.md`.
- Alert on evaluation errors, provider lag, and SDK bootstrap failures: silent flag failures default to unknown behavior.
- Report flag age distribution and expired-flag count as a recurring engineering-health metric.
- Record flag changes (who flipped what, when) in the same audit path as deploys; a flag flip is a production change.

## Rollout Runbook

1. Confirm the flag evaluates to the intended default in every environment before any exposure.
2. Enable for internal accounts; verify the success metric and guardrails for a defined window.
3. Expand to named customers, then percentage rings, pausing long enough for metrics to be meaningful.
4. At each step, compare variant metrics against the control, not against last week.
5. On guardrail breach, disable the flag first and investigate second; the flag is the fast lever. See `./07-observability-rollback.md`.
6. At full exposure, start the cleanup clock: remove the losing path, then archive the flag.
7. Record each step with actor and timestamp so the rollout can be reconstructed later.

## Migration Notes

- Moving from env-var toggles to a flag system: create the flag with the same default, switch reads one at a time, then remove the env variable. Never remove an env toggle and add a flag in the same release.
- Moving from one provider to another: run both SDKs in shadow mode and compare evaluations before cutting over; bulk-import targeting rules and audit the diff.
- Retiring an experiment flag: choose the winning variant, remove the losing code path, keep the flag record for history, then archive.
- Converting a release flag to permanent configuration: reclassify, move it to the config system with review, and document it in the service's config schema.
- Cleaning up after a provider migration: archive flags in the old system only after the new system has served production traffic for a full release cycle.

## Anti-Patterns

- Flags as a permanent configuration system with no cleanup.
- Nested flags and combinatorial branches nobody can reason about.
- Provider dependency on the request path with no cache or fallback.
- Experimental flags used to gate safety-critical behavior without a fail-safe default.
- One flag controlling unrelated behaviors ("the new stuff" flag).
- Rolling out to 100 percent with no metric defined and no rollback criteria.
- Client-side flags hiding features whose payloads remain fully accessible.
- Flags without owners whose creator left the team.
- Testing only the on state, then discovering the off path is broken during an incident.
- Kill switches never exercised; the first use fails.

## Checklist

- [ ] Every flag classified and carries owner, expiry, and cleanup ticket.
- [ ] Defaults chosen per flag for provider outage, explicitly documented.
- [ ] Evaluation is local and cached on request paths; bootstrap snapshot exists.
- [ ] Targeting uses stable, sticky bucketing.
- [ ] Exposure plan defined with metrics and numeric rollback criteria.
- [ ] Flag dependencies documented.
- [ ] Tests cover on and off paths plus provider-unavailable defaults.
- [ ] Flag debt dashboard exists; expired flags have owners and deadlines.
- [ ] Cleanup removes code, not just flips state.
- [ ] Kill switches exercised in a game day at least twice a year.
