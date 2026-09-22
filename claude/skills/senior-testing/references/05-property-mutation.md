# Property-Based and Mutation Testing

Proving invariants over input classes with generated data, and measuring whether assertions actually constrain behavior.

## Why Examples Are Not Enough

Example-based tests verify the cases the author thought of. They systematically miss:

- Boundary values the author forgot (empty, max, unicode, overflow).
- Combinations of features (e.g. discount + tax + rounding together).
- Round-trip and ordering invariants that should hold for all inputs.
- Code paths that only fail for rare structures.

Property-based testing (PBT) generates hundreds of inputs per test and validates a
statement that must hold for all of them. It is the cheapest way to find the edge cases
you did not enumerate.

## Property-Based Testing Model

```text
for all x satisfying preconditions:
    assert invariant(f(x))
```

A property is one of:

| Property kind | Statement | Example |
|---|---|---|
| Round-trip | decode(encode(x)) == x | JSON, protobuf, compression |
| Invariant | predicate holds after operation | balance never negative |
| Idempotence | f(f(x)) == f(x) | normalization, deduplication |
| Commutativity | f(a, b) == f(b, a) | set union, merge |
| Associativity | f(f(a, b), c) == f(a, f(b, c)) | aggregation |
| Oracle | compare with a simple reference implementation | fast path vs slow path |
| Metamorphic | relationship between inputs and outputs | sorting preserves multiset |
| Safety/liveness | bad states unreachable; good states eventually reached | state machines |

### Tooling by language

| Language | Library | Notes |
|---|---|---|
| Python | Hypothesis | Best-in-class shrinking and stateful testing; works with pytest |
| TypeScript/JS | fast-check | Integrates with Jest/Vitest; model-based `fc.commands` |
| Rust | proptest, quickcheck | proptest has composable strategies and shrinking |
| Go | rapid (native testing integration), gopter | rapid by the Go team, fast |
| Java/Kotlin | jqwik | JUnit 5 platform; strong shrinking; stateful `ActionSequence` |
| C# | FsCheck, CsCheck | FsCheck mature; CsCheck high performance |
| Elixir | StreamData | Pairs with ExUnit |
| Scala | ScalaCheck | The original inspiration |

All of these are stable but release at different cadences; pin versions and verify current
APIs upstream.

## Writing Properties (Python / Hypothesis)

```python
from decimal import Decimal

from hypothesis import given, strategies as st

money = st.decimals(min_value=Decimal("0"), max_value=Decimal("999999.99"), places=2)

@given(money, money)
def test_addition_is_commutative(a: Decimal, b: Decimal) -> None:
    assert add_amounts(a, b) == add_amounts(b, a)

@given(st.lists(st.integers()))
def test_sort_preserves_multiset(xs: list[int]) -> None:
    assert sorted(xs) == sorted(sorted(xs))
    assert len(sorted(xs)) == len(xs)
```

Practical guidance:

- Pair every property test with at least one example test for the documented cases and a
  regression `@example` for bugs found in production.
- Constrain strategies to the real domain (`min_value`, `places`, custom composite
  strategies) instead of filtering everything with `assume` — filters make generation slow
  and hide the domain model.
- Use `@example(...)` to keep permanent regressions deterministic.
- Record the seed from failures: Hypothesis prints `Falsifying example` and the seed;
  reproduce with `--hypothesis-seed=<seed>`.
- In CI, allow a larger `max_examples`, but keep PR runs bounded (for example 100-200
  examples) to protect the time budget.
- `derandomize=True` gives reproducible runs at the cost of exploration; use it when
  debugging, not as the default in nightly.
- Hypothesis profiles make this explicit: `ci` vs `dev` vs `debug`.

### Strategy design

```python
from hypothesis import strategies as st

emails = st.builds(
    lambda user, domain: f"{user}@{domain}",
    user=st.text(alphabet="abcdefghijklmnopqrstuvwxyz0123456789._-", min_size=1, max_size=32),
    domain=st.sampled_from(["example.com", "test.example.org"]),
)
```

- Build domain objects with `st.builds`/`composite` so failures look like real inputs.
- Model optionality with `st.none() | st.text()` rather than filtering.
- Keep collections bounded (`max_size`) to prevent memory blowups.
- Avoid `st.floats()` without bounds for domain values that are never NaN or infinite.

## Shrinking

Shrinking is the process of reducing a failing input to its minimal form. It is what makes
a PBT failure actionable instead of a 3000-character blob.

How to make shrinking effective:

- Do not transform inputs destructively; libraries shrink the original, so derived values
  must be deterministic functions of it.
- Write preconditions as strategy constraints, not `assume`, so the search space is valid
  by construction.
- Never swallow exceptions in the property; a `try/except: pass` defeats both detection
  and shrinking.
- When a custom strategy generates opaque IDs, shrink the components (strings, ints) that
  compose them.
- If a failure does not shrink well, add a dedicated `@example` with the minimal case and
  fix the strategy separately.

## Stateful / Model-Based Testing

For objects with lifecycle (caches, sessions, retries, state machines), generate sequences
of operations and check invariants after each step.

```python
from hypothesis.stateful import RuleBasedStateMachine, rule, invariant

class CartMachine(RuleBasedStateMachine):
    @rule(price=st.integers(min_value=0, max_value=10_000))
    def add_item(self, price: int) -> None:
        self.cart.add(price)

    @rule()
    def checkout(self) -> None:
        self.cart.checkout()

    @invariant()
    def total_never_negative(self) -> None:
        assert self.cart.total >= 0
```

- Keep a simple reference model in the test and compare after each operation (oracle
  pattern).
- Use stateful testing for idempotent consumers, retry logic, and any state machine whose
  transition table is non-trivial.
- Bound the sequence length so runs stay fast; the shrinker handles the rest.

## Mutation Testing

Mutation testing answers: "if this code were wrong, would any test fail?" It modifies the
program (flips `>=` to `>`, replaces `+` with `-`, negates conditions, removes statements)
and re-runs the suite. A mutant that survives means a real defect class you do not detect.

### Tools

| Ecosystem | Tool | Notes |
|---|---|---|
| JS/TS | StrykerJS | Supports Jest, Vitest, Mocha; incremental mode |
| Java/Kotlin | PIT (pitest) | Fast, JUnit 5 integration, Maven/Gradle plugins |
| .NET | Stryker.NET | Similar model to StrykerJS |
| Rust | cargo-mutants | Crate-aware; respects workspaces; emits mutants report |
| Python | mutmut, cosmic-ray | Slower; scope to hot modules |
| Go | go-mutesting, gremlins | gremlins is actively maintained; verify upstream |

### Metrics

| Metric | Definition | Interpretation |
|---|---|---|
| Mutation score | killed / (killed + survived) | Overall assertion strength |
| Killed | Test failed because of the mutation | Good |
| Survived | All tests passed with mutated code | Missing/weak assertion |
| No coverage | No test executed the mutated line | Coverage gap |
| Timeout | Tests hung on the mutant | Usually counted as killed; investigate |
| Equivalent mutant | Mutation preserves semantics | False positive; ignore with reason |

### Making mutation testing practical

Mutation testing is 10-100x the cost of the test suite, so treat it as a **scoped gate**:

- Run it on changed files only in PRs (incremental/diff mode), and on the full critical
  modules nightly.
- Exclude generated code, migrations, DTOs, and configuration.
- Set a threshold per module: for example >= 80% on domain modules, report-only elsewhere.
  Never set a repo-wide percentage that forces people to write trivia tests.
- Surviving mutants in domain logic are action items with owners; surviving mutants in
  logging/config are noise — suppress with a reason.
- Use it to find missing assertions, not to reach 100%. The interesting output is the list
  of surviving mutants, not the score.
- Combine with PBT: property tests kill many mutants that example tests miss, especially
  boundary mutants.

### Interpreting survivors

| Survivor pattern | Meaning | Fix |
|---|---|---|
| Boundary flipped and tests still pass | No tests at the exact edge | Add boundary example or property |
| Return value ignored | Assertion only checks "no exception" | Assert the value |
| Condition removal survives | Dead branch or untested error path | Delete dead code or test the path |
| String literal changed | Snapshot/assertion too loose | Pin exact contract values |
| Off-by-one in loop | Untested collection sizes | Property test with variable lengths |
| Short-circuit reordering | Test lacks side-effect assertion | Assert side effects explicitly |

## Quality Gates

| Gate | Where | Threshold guidance |
|---|---|---|
| Property tests on core invariants | PR | Required for pure domain functions with stated invariants |
| Regression example for each escaped bug | PR | Always; cheapest possible regression |
| Diff mutation score on touched domain files | PR | >= 80% on domain modules, report elsewhere |
| Full mutation run | Nightly | Trend over time; investigate regressions, not absolute |
| Equivalent-mutant suppressions | Review | Each suppression has a comment and reviewer approval |

## Anti-Patterns

- Property tests with no properties ("re-run the implementation and compare").
- Using `assume` for the majority of generated inputs; generation becomes slow and shallow.
- Ignoring the falsifying example and re-running until green.
- Mutation score as a vanity metric with repo-wide 100% targets.
- Testing `getters` for mutation coverage; spend the budget on branching logic.
- Suppressing mutants without a reason or owner.
- Letting PBT run unbounded in the PR gate; cap examples and time.
- Copying a property from a tutorial without adapting the strategy to the domain.

## Checklist

- [ ] Core domain invariants have property tests (round-trip, idempotence, invariants,
      oracle).
- [ ] Strategies model the domain (bounds, composites) rather than filtering broadly.
- [ ] Every production bug adds a deterministic regression example.
- [ ] Shrinking works: failures report minimal inputs.
- [ ] Stateful testing covers at least one lifecycle object in the codebase.
- [ ] Mutation testing runs incrementally on changed domain files in PRs.
- [ ] Surviving mutants are triaged with owners; suppressions are justified.
- [ ] PR property runs are time-bounded; nightly runs explore more.
