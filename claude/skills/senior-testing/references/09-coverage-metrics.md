# Coverage and Quality Metrics

Measuring what tests actually verify, setting honest gates, and building dashboards that drive improvement rather than gaming.

## Coverage Types

| Metric | Measures | Blind spot |
|---|---|---|
| Line/statement | Executed lines | Branches, assertions |
| Branch | Both outcomes of conditionals | Assertion strength, data interactions |
| Function | Called functions | Untested inputs within function |
| Path | Combinations through a function | Grows exponentially; rarely usable |
| MC/DC | Condition independence (safety-critical) | Expensive tooling; overkill for most apps |
| Diff/patch | Coverage of changed lines | Untested old code on the same path |
| Requirement | Mapped tests to requirements | Manual mapping cost |

Coverage tells you what code ran, never whether the result was checked. A suite with 95%
line coverage and no assertions has the same defect-detection power as no tests at all
([05-property-mutation](./05-property-mutation.md) measures the missing piece).

## Why Coverage Is Easy to Game

| Behavior | Metric effect | Actual quality |
|---|---|---|
| Assertion-free "smoke" tests | Coverage up | Unchanged |
| Testing trivial getters | Coverage up | Negligible |
| `# pragma: no cover` on hard code | Coverage up | Hidden risk |
| Excluding modules from the tool config | Coverage number up | Hidden risk |
| One giant test calling everything | Coverage up | Failures ambiguous |
| Snapshot tests with auto-update in CI | Coverage up | Tautological verification |
| Duplicating production logic in tests | Branches covered | Independent bugs cancel out |

Because targets are easy to game, coverage should be a **diagnostic** (find untested
critical code) with a **low, honest gate**, not a primary goal.

## Setting Coverage Gates

Guidance that survives contact with real teams:

- Use **branch coverage** with a modest global floor (for example 70-80%) and strict
  review of exclusions.
- Prefer **diff coverage** on the PR (for example >= 80% of changed lines) plus component-
  level floors. Global numbers move too slowly to guide daily work and are dominated by
  legacy code.
- Set **component-specific targets** by risk: domain and payment logic 90%+, glue and
  adapters 60%, generated code excluded.
- Never allow coverage to *drop* on touched modules: ratchet per directory over time.
- Exclude only with reasons: generated files, platform shims, `if TYPE_CHECKING`, vendored
  code. Every exclusion is reviewed in the config file's own PR.
- Treat "coverage down 0.1%" PR failures as a false-positive generator; use rounded
  thresholds and allow documented exceptions.

```toml
# coverage.py / pytest-cov style
[tool.coverage.run]
branch = true
source = ["src"]

[tool.coverage.report]
fail_under = 75
show_missing = true
exclude_also = [
  "if TYPE_CHECKING:",
  "raise NotImplementedError",
  "class .*Protocol.*:",
]
```

```yaml
# diff coverage gate in CI (concept; use your coverage tool's diff mode)
quality-gate:
  diff-coverage-min: 80
  component-floors:
    src/domain: 90
    src/adapters: 60
```

## Diff Coverage in Practice

Diff coverage answers: "of the lines this PR changes or adds, how many are executed by
tests in the repo?" It is the most actionable coverage gate because it is local to the
change and cannot be diluted by legacy code.

Workflow:

1. Run the suite with coverage and emit machine-readable output (`coverage json`,
   `cobertura`, `lcov`).
2. Compute coverage restricted to the PR diff (tools: diff-cover, codecov patch status,
   Sonar new-code mode).
3. Fail the check when below the threshold; allow explicit waivers for pure refactors
   where lines moved without change.
4. Require an explanation when new error-handling branches are uncovered — those are
   exactly where defects hide.

Caveats:

- Renames and moves inflate or deflate the diff; restrict to added/modified lines.
- Generated or vendored diffs must be excluded before computing.
- Do not gate on deleted lines; deletion decreases code and should not require tests.

## Mutation Score as a Stronger Signal

Mutation score measures the fraction of seeded faults the suite detects, so it
approximates assertion strength.

| Signal | Weak suite | Strong suite |
|---|---|---|
| Line coverage | 90% | 90% |
| Mutation score | 40% | 85% |
| Flake rate | 5% | < 0.5% |

How to use it without drowning:

- Run incrementally on changed files in PRs; run full on core modules nightly
  ([05-property-mutation](./05-property-mutation.md)).
- Gate on domain modules with a meaningful threshold (for example >= 80%), report-only
  elsewhere.
- Track survivors as a backlog of specific missing assertions, not a global percentage.
- Suppress equivalent mutants with a written reason; review suppressions like code.

## Runtime and Flake Metrics

Test quality is not only coverage:

| Metric | Target guidance | Purpose |
|---|---|---|
| PR gate duration p95 | <= 15 min | Developer feedback loop |
| Fast suite duration | <= 5 min | Inner loop viability |
| Flake rate per suite | < 1% | Trust in red |
| Quarantine size | < 2% of tests, all with expiry | Avoid graveyards |
| Mean time to fix flake | <= 14 days | Enforcement of ownership |
| Retry rate | < 2% of executions | Hidden instability |
| Test maintenance ratio | ~10-20% of eng time | Sustainability |

A suite that is fast and reliable but shallow (low mutation score) and a suite that is deep
but flaky are both unhealthy; dashboards should show both axes.

## DORA and Delivery Metrics Alongside Tests

Test metrics answer "is our verification good?"; DORA answers "is our delivery system
good?" Track both, understanding the causal links.

| Metric | Definition | Test-suite relationship |
|---|---|---|
| Deployment frequency | Deploys to production per period | Fast CI enables smaller, more frequent releases |
| Lead time for changes | Commit to production | Test runtime is a leading component |
| Change failure rate | Deploys causing degradation | Low change failure rate with high coverage/mutation suggests tests work |
| Failed deployment recovery time | Time to restore service | Fast, trusted suites shorten recovery and enable reverts |

Use DORA trends to calibrate test investment: if lead time is dominated by CI waits, the
fix is test speed and sharding, not more tests. If change failure rate is high while
coverage is high, the tests are shallow — raise assertion strength with mutation and
property testing, not coverage.

## Dashboards That Do Not Mislead

Rules for quality dashboards:

1. **Show trends, not just snapshots.** A 72% coverage that rose from 60% is healthy; a
   flat 85% with rising flake is not.
2. **Show distributions.** Per-module coverage or mutation, not one global average that
   hides a 10% critical module.
3. **Pair every headline with a guardrail.** Coverage next to flake rate and gate duration;
   DORA next to coverage and mutation.
4. **Make ownership visible.** Color or group by owner so the right team sees their row.
5. **Never show individual rankings.** Per-person test metrics create gaming and blame;
   aggregate by team or component.
6. **Define each metric on the dashboard** with its formula and data source; undefined
   metrics get re-litigated monthly.
7. **Alert on regressions, not absolute values** (coverage dropped > 2 points after a
   merge; flake rate doubled week over week).
8. **Retire metrics nobody acts on.** A dashboard with 40 panels is wallpaper; keep fewer
   than 10 actionable signals.

## Anti-Patterns

- 100% coverage mandates; teams write assertion-free tests, and the number is meaningless.
- Comparing coverage across languages or repositories as a team performance metric.
- Ignoring flake while raising coverage; the suite becomes both slow and untrusted.
- Using coverage as a performance review input.
- Hiding critical modules behind exclude lists to pass the gate.
- Dashboards that count test *cases* rather than risk covered; 5000 trivial tests is not
  better than 300 meaningful ones.
- Treating DORA metrics as individual performance scores rather than system signals.
- Chasing path coverage or MC/DC outside safety-critical or regulated contexts.

## Metrics Checklist

- [ ] Coverage collected in branch mode for source code only.
- [ ] Global floor modest; per-component floors risk-weighted.
- [ ] Diff coverage gates every PR; waivers are explicit.
- [ ] Exclusions are reviewed, reasoned, and few.
- [ ] Mutation score gates domain modules incrementally; survivors triaged.
- [ ] Flake rate, retry rate, and quarantine size tracked with owners and expiries
      ([08-flaky-ci](./08-flaky-ci.md)).
- [ ] PR gate duration tracked against the 15-minute budget.
- [ ] DORA metrics reported alongside test metrics to explain causal links.
- [ ] Dashboard shows trends, distributions, and owner groupings; under 10 actionable
      panels.
- [ ] Every gate has a stated purpose and an owner; useless gates are removed.
