# Modularity and Boundaries

Module boundary design, dependency direction, package principles, and fitness functions that
enforce them in CI.

## Why Boundaries

A boundary is a contract about what may change together. Good boundaries let teams change one
part of a system without understanding or redeploying the rest. Bad ones are either absent (big
ball of mud) or wrong (cut by layer or framework), and both guarantee that every change touches
everything.

A real boundary has: an owner, an explicit public surface, its own data (or an explicit
delegation), a defined dependency direction, and an enforcement mechanism.

## Boundary Heuristics

Cut along lines where change is likely to be local:

| Axis | Cut here | Avoid |
|---|---|---|
| Business capability | "Pricing", "Fulfillment", "Identity" | "Utils", "Common", "Core" |
| Data ownership | One writer per data set | Shared tables between modules |
| Rate of change | Volatile UI versus stable domain rules | Mixing slow domain with fast integrations |
| Volatility of external dependency | Isolate each vendor behind an adapter | Vendor SDK imported across the codebase |
| Compliance/trust | Payment data, PII processing isolated | PII in shared DTOs and logs |
| Team ownership | One team accountable per boundary | Joint ownership of the same module |
| Scaling profile | Hot path separated from batch/CPU-heavy work | One module doing both |

Common failure: boundaries drawn by technical layer (`controllers`, `services`, `repositories`).
Layer boundaries are deployment conveniences; feature/capability boundaries are the ones that
survive product change.

## Dependency Direction

Rules:

1. **Dependencies point toward stability.** Stable, abstract policy must not depend on volatile
   detail. Domain and application policy sit at the center; transport, persistence, and vendor
   code sit at the edge.
2. **No cycles.** A dependency cycle between modules means they are one module; break it or merge
   them.
3. **Ports and adapters.** Domain defines interfaces (ports) it needs; infrastructure implements
   them (adapters). Inversion, not direction, is the mechanism.
4. **Cross-boundary calls only through the public surface.** No reaching into another module's
   internal packages, tables, or DTOs.
5. **Shared kernel is explicit and tiny.** If code is used by many modules, either promote it to
   a versioned library with an owner or accept duplication.
6. **Data flows through APIs/events, not shared schema.** See
   [./06-data-architecture.md](./06-data-architecture.md).

Layering reference (adapt per style):

```
interfaces/transport  ->  application/use-cases  ->  domain  <-  infrastructure adapters
       (depends inward)        (depends inward)      (depends on nothing technical)
```

## Package Principles

Robert Martin's package principles; useful as review questions rather than dogma.

| Principle | Name | Rule |
|---|---|---|
| REP | Reuse/Release Equivalence | Classes in a package are released together and reusable together; the package is the unit of versioning |
| CCP | Common Closure | Classes that change for the same reasons belong together (SRP at package scale) |
| CRP | Common Reuse | Classes used together belong together; do not force consumers to depend on things they do not use |
| ADP | Acyclic Dependencies | No cycles in the package dependency graph |
| SDP | Stable Dependencies | Depend in the direction of stability (fewer incoming/outgoing churn) |
| SAP | Stable Abstractions | Stable packages should be abstract; volatile packages concrete |

Tension to manage consciously: CCP and CRP pull in opposite directions (bundle by change vs
bundle by use). Resolve per context, not globally; domain-heavy packages favor CCP, utility
libraries favor CRP.

## Coupling Metrics

Compute these on the module graph in CI and trend them; absolute values matter less than
direction.

| Metric | Meaning | Formula |
|---|---|---|
| Ca (afferent) | Modules depending on this one | count of incoming deps |
| Ce (efferent) | Modules this one depends on | count of outgoing deps |
| Instability I | Exposure to change | `I = Ce / (Ca + Ce)`; 0 = stable, 1 = unstable |
| Abstractness A | Ratio of abstract types | `A = abstract types / total types` |
| Distance from main sequence D | Balance | `D = |A + I - 1|`; aim small for nontrivial modules |

Use metrics to start conversations, not to gate builds: a high-D module is a question ("is this
stable package full of concrete details, or a volatile package full of abstractions?"). Cyclic
counts, cross-boundary violation counts, and fan-in of "common" modules are better CI gates than
D thresholds.

## Fitness Functions

A fitness function is an automated test of an architectural property. Put them in the normal
test suite so they fail pull requests, not quarterly reviews.

### Java (ArchUnit, 1.x; verify current upstream)

```java
@AnalyzeClasses(packages = "com.acme.orders")
class ArchitectureTest {

  @ArchTest
  static final ArchRule domain_is_isolated = noClasses()
      .that().resideInAPackage("..domain..")
      .should().dependOnClassesThat()
      .resideInAnyPackage("..infrastructure..", "..interfaces..");

  @ArchTest
  static final ArchRule no_cycles = slices()
      .matching("com.acme.orders.(*)..")
      .should().beFreeOfCycles();
}
```

### TypeScript/JavaScript (dependency-cruiser, verify current upstream)

```js
// .dependency-cruiser.cjs
module.exports = {
  forbidden: [
    {
      name: "domain-shall-not-import-infra",
      severity: "error",
      from: { path: "^(src/[^/]+)/domain" },
      to: { path: "^(src/[^/]+)/(infrastructure|http|db)" },
    },
    {
      name: "no-circular",
      severity: "error",
      from: {},
      to: { circular: true },
    },
  ],
  options: { tsConfig: { fileName: "tsconfig.json" } },
};
```

ESLint equivalent for a single rule (no extra tooling):

```js
"no-restricted-imports": ["error", {
  patterns: [
    { group: ["**/infrastructure/**"], message: "Domain code must not import infrastructure." }
  ]
}]
```

### Python (import-linter, 2.x; verify current upstream)

```ini
# setup.cfg
[importlinter]
root_package = acme

[importlinter:contract:layers]
name = Layered architecture
type = layers
layers =
    acme.interfaces
    acme.application
    acme.domain
```

Run in CI: `lint-imports` for Python, `depcruise --validate .dependency-cruiser.cjs src` for
TypeScript, and the ArchUnit test as part of the standard test task.

### Go

- `internal/` under a parent package is import-restricted by the toolchain.
- `go list -deps ./...` plus a small script can assert forbidden edges; `arch-go` and similar
  linters add rule configuration (verify current upstream).

### Reviews and CODEOWNERS

- CODEOWNERS maps boundaries to reviewers, so cross-boundary changes get the right eyes.
- Multi-repo: use build-system visibility (Bazel `visibility`, workspace package boundaries) or
  a service catalog that records allowed dependencies.

Properties worth enforcing, in rough priority:

1. No dependency cycles between top-level modules.
2. Domain does not import transport/persistence/framework code.
3. Cross-module imports only via the module's public package/path.
4. Specific banned edges (for example `billing -> shipping`) where the context map says
   separate ways or customer/supplier only.
5. No direct datastore access across module boundaries (no shared table names, no shared ORM
   models).

## Public Surface Design

- One module = one public package (or `exports` map, `__all__`, `api/` path). Everything else is
  internal by convention and by tooling.
- Version the public surface with semantic versioning; treat it as an API even inside a monorepo
  (see the monorepo pack for workspace versioning).
- Export types/contracts, not implementations: interfaces, DTOs, events.
- Avoid leaky abstractions: no framework types in the public signature unless the framework is
  part of the contract.
- Deprecate in the surface, remove after a published window.

## Shared Code Strategy

| Option | Use when | Cost |
|---|---|---|
| Duplicate | Logic is small and stable; coupling would be wrong | Drift risk; acceptable for < a few hundred lines |
| Shared kernel module | Genuinely universal concepts (money, ids, time) | Any change touches all consumers; keep tiny |
| Internal library (versioned) | Multiple teams, different release cadences | Release management overhead |
| Copy-on-write with codemod | Broad mechanical change | Requires tooling discipline |

Prefer duplication over the wrong abstraction when the shared piece encodes different business
meaning in each context (a `Customer` in billing is not the `Customer` in support).

## Anti-Patterns

- **Layer-only packages** — `utils`, `common`, `core` as dumping grounds with fan-in from
  everywhere.
- **Boundary in name only** — folders with no dependency enforcement; the first deadline erases
  them.
- **Distributed boundary** — a module that shares tables or transactions with another module.
- **Fitness function theater** — rules so weak or excluded that they never fail; verify they
  catch a planted violation.
- **Over-modularization** — a dozen packages for a small app; navigation and release overhead
  for no autonomy gain.
- **Big shared kernel** — half the model lives in `shared`; boundaries are cosmetic.
- **Rules only for juniors** — seniors bypass the checks; then the checks stop mattering.

## Checklist

- [ ] Boundaries named by capability, each with an owner.
- [ ] Public surface documented and minimal.
- [ ] Dependency direction enforced (no domain -> infrastructure edges).
- [ ] No cycles between modules; trend measured in CI.
- [ ] Fitness functions run on every pull request and can actually fail.
- [ ] Cross-boundary data goes through APIs/events, never shared tables.
- [ ] Shared code decision recorded (duplicate, kernel, or library) per case.
- [ ] CODEOWNERS or equivalent routes boundary changes to owners.
- [ ] New violations are visible in review, not discovered at release.

## Related

- Domain boundaries that these modules implement: [./04-ddd.md](./04-ddd.md)
- Style choice that determines deployment boundaries: [./03-styles.md](./03-styles.md)
- Extracting a module along an enforced seam: [./08-migration-evolution.md](./08-migration-evolution.md)
