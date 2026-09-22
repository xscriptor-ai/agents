# AI-Assisted Test Generation

Using LLMs to draft tests safely: review requirements, adversarial coverage, prompt patterns, and the failure modes that make generated tests dangerous.

## What LLMs Are Good and Bad At

| Task | LLM strength | Risk |
|---|---|---|
| Drafting happy-path example tests | High productivity | Shallow coverage, over-fitting to visible code |
| Enumerating edge cases | Good with explicit prompting | Invents domain rules that do not exist |
| Writing factories/builders | Strong, mechanical | Overly permissive or invalid defaults |
| Translating existing tests between frameworks | Strong | Silent behavior differences between frameworks |
| Property identification | Moderate | Proposes tautologies, re-implements the code |
| Finding missing branches | Useful as a reviewer | Hallucinated APIs and assertions |
| Diagnosing flaky tests from artifacts | Moderate | Confident wrong conclusions; verify evidence |
| Writing adversarial/security tests | Good when primed | May generate unsafe payloads without sandboxing |

Use LLMs to accelerate **drafting and enumeration**, never to replace human ownership of
what a test asserts and why.

## Non-Negotiable Review Requirements

1. **Every generated test is reviewed like production code.** Same PR, same checklist,
   same CODEOWNERS.
2. **Run it. Do not merge untested tests.** Verify they fail when the behavior is wrong:
   mutate the code or temporarily break the assertion to confirm the test can go red
   ([05-property-mutation](./05-property-mutation.md)).
3. **Verify every API and import against the real codebase and the installed library
   version.** Hallucinated methods are the most common defect.
4. **Human sign-off on assertions.** The reviewer must be able to explain what defect
   each assertion catches.
5. **No generated test may touch production data, real credentials, or live third-party
   services.**
6. **Label provenance when the process requires it** (a commit trailer or PR note), so
   audits can trace AI-generated code.

## Failure Modes of Generated Tests

| Failure mode | Symptom | Detection |
|---|---|---|
| Hallucinated API | Test references methods/classes that do not exist | Compiler/type checker, test run |
| Tautological assertion | `assert result == result`, asserts on the mock | Mutation testing; careful reading |
| Re-implementation | Test re-computes expected value with the same logic as production | Independent expected value or fixed example |
| Over-mocking | Test passes regardless of production bugs | Remove mocks where possible; integration layer |
| Happy-path bias | No error, boundary, or permission cases | Coverage of error branches; mutation survivors |
| Non-deterministic data | Uses `datetime.now()`, random without seed | Determinism review, run in CI repeatedly |
| Wrong framework idioms | Jest patterns in Vitest, pytest fixtures misused | Lint/runner failures; framework review |
| Silent assertion weakening | `assert x is not None` where equality mattered | Mutation score drop |
| Copy-paste naming | Ten tests with near-identical bodies | Deduplicate via parameterization |
| Sensitive data invention | Realistic PII or tokens in fixtures | PII scanning in CI ([07-test-data](./07-test-data.md)) |

The cheapest defense is the existing pipeline: types, linters, the test run itself, and
mutation testing. The human review catches the semantic failures the pipeline cannot.

## Prompt Patterns That Work

### Enumerate first, write second

```text
Given this function and its docstring:
1. List the input classes and boundaries.
2. List the error conditions and how they surface.
3. Only then write one parameterized test per class.
Do not invent domain rules not present in the code or docstring.
```

Separating enumeration from code generation makes wrong assumptions visible before they
are buried in test bodies.

### Anchor on the specification

```text
Here is the OpenAPI schema / RFC section / ADR for this behavior.
Write tests only for behavior specified there.
For anything not specified, list open questions instead of guessing.
```

### Adversarial pass

```text
Review this existing test file as a skeptical reviewer.
For each test, name the defect it would catch.
Then list behaviors with no test: error paths, boundaries, permissions,
concurrency, idempotency. Output a prioritized list; do not write code yet.
```

### Property extraction

```text
Identify properties that must hold for all inputs (round-trip, idempotence,
invariants, ordering). For each, state it formally and propose a strategy.
Flag any property that merely restates the implementation.
```

### Regression from a bug report

```text
Here is the bug report with reproduction steps and the fix diff.
Write a test that fails on the pre-fix code and passes on the fixed code.
The test must assert the user-visible outcome, not the implementation detail
that changed.
```

This is one of the highest-value uses of LLMs: converting incident descriptions into
deterministic regression tests, then verifying the red/green transition.

### Flake diagnosis

```text
Here is the failing log, the trace summary, and the test source.
List plausible causes ranked by evidence. For each, state what evidence would
confirm or refute it. Do not propose a fix until the cause is identified.
```

The constraint "do not fix until diagnosed" prevents the common AI-suggested
`sleep`/retry patch that hides the race.

## Adversarial and Security Cases

LLMs are effective at enumerating hostile inputs; treat their output as candidates, not
production payloads.

- Generate boundary and injection candidates (long strings, unicode edge cases, mixed
  encodings, nested structures, negative numbers, overflow) for validation logic.
- Keep security tests in a quarantined fixture set: no live exploits, no payloads against
  systems you do not own.
- For authz, generate the full role x action x resource matrix and assert denials
  explicitly; this is where models find gaps humans forget.
- Fuzz-like generation belongs in property-based testing with a seed, not in ad-hoc
  generated strings ([05-property-mutation](./05-property-mutation.md)).

## Workflow and Governance

Recommended pipeline:

1. **Draft** — LLM proposes test skeletons and case lists, human picks the important ones.
2. **Constrain** — project conventions injected via prompt or rules file: framework,
   fixtures/factories, naming, no sleeps, no real network, unique per-run data.
3. **Verify locally** — run, type-check, lint. Delete anything that cannot run.
4. **Prove sensitivity** — break the implementation intentionally and confirm the test
   fails; restore.
5. **Review** — human reviewer checks assertions, determinism, layering, and data hygiene.
6. **Merge** — same gate as handwritten tests; gate coverage/mutation applies.
7. **Monitor** — track AI-drafted tests for flake and mutation survival separately at
   first; a spike indicates a prompting or review gap.

Governance decisions to make explicitly:

- Whether AI-generated tests may be committed and under what provenance labeling.
- Which repositories are off-limits (regulated, or containing sensitive logic).
- Whether prompt/context may include proprietary source (check provider data policies).
- Who owns an AI-drafted test once merged — the code owner, same as any test.

## Anti-Patterns

- Merging generated tests without running them.
- Accepting assertions you cannot explain.
- Generating hundreds of shallow tests to raise coverage
  ([09-coverage-metrics](./09-coverage-metrics.md)).
- Letting the model write the expected value by re-running the implementation.
- Prompting with production code containing secrets or customer data.
- Using generated security payloads against live systems.
- Trusting a model's "these tests pass" without executing them.
- Replacing human test design with prompting; ownership and judgment stay human.

## Checklist

- [ ] Generated tests run, type-check, and lint in the same pipeline as handwritten tests.
- [ ] Every assertion maps to a stated defect class; reviewer can explain each one.
- [ ] APIs, imports, and fixtures verified against the real codebase and installed
      versions.
- [ ] Sensitivity verified: at least one intentional break makes each new test fail.
- [ ] Determinism verified: no wall clock, unseeded randomness, real network, or shared
      state.
- [ ] Data is synthetic and unique per run; no PII, tokens, or production extracts.
- [ ] Duplicate/copy-paste tests consolidated via parameterization.
- [ ] Provenance policy applied; off-limits repositories respected.
- [ ] Flake and mutation outcomes tracked for AI-drafted tests until the process matures.
