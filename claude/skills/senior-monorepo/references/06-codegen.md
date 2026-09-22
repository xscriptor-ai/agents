# Code Generation

> Scope: workspace generators, schema-to-types pipelines, protobuf/OpenAPI codegen, and keeping generated code consistent with its source of truth.

Generation is how a monorepo keeps N consumers aligned with one schema. Every generated artifact has exactly one source of truth, one generator, and one drift check.

## 1. Generation taxonomy

| Kind | Examples | Source of truth | Output |
| --- | --- | --- | --- |
| Scaffolding | new package/app/component | template + prompts | new files, reviewed once |
| Schema-first types | OpenAPI, GraphQL, JSON Schema | `openapi.yaml`, `schema.graphql`, `.json` | typed clients, validators |
| Protocol | protobuf, Thrift, Avro | `.proto` files | messages, stubs, clients |
| Data layer | SQL, ORM schema | migrations, `schema.prisma`, SQL files | query types, client code |
| Infra | IaC, k8s manifests | templates + values | rendered YAML |
| Config | env schema, feature flags | schema definition | typed accessors, docs |

If an artifact has no schema or template in the repository, it does not belong in a codegen pipeline.

## 2. Workspace generators

Generators create consistent packages so humans do not hand-roll config.

| Tool | Fit | Notes |
| --- | --- | --- |
| Nx generators | Nx workspaces | `nx g @nx/js:lib`, `@nx/react:component`; local plugins for org templates |
| `turbo gen` | Turborepo | generators as workspace packages; good for lightweight scaffolds |
| Plop | any repo | interactive prompts + templates; simple and framework-free |
| Hygen | any repo | file-per-template, fast, script-friendly |
| Yeoman | any repo | older but still maintainable; heavier |
| Custom scripts | any repo | acceptable for one or two scaffolds; do not reinvent Nx |

Rules for generators:

- The generator is the only way to create a package; PR review for `packages/*` assumes generated wiring.
- Generated packages include tests, README, ownership entry, and CI visibility from birth (tags, catalog entries, workspace globs are automatic).
- Generators are tested: run the generator in CI against a temp workspace and assert the output builds.
- Keep prompts minimal; support non-interactive flags (`--name`, `--scope`, `--dry-run`) for scripting.
- Version generators with the tool they generate for (Nx plugin major follows Nx major).
- When a convention changes, update the generator and codemod existing packages; do not leave both forms alive.

Example local generator layout (Nx):

```
tools/generators/lib/
  index.ts          # generator entry: options, files, install
  files/
    package.json.template
    tsconfig.json.template
    src/index.ts.template
  index.spec.ts     # runs the generator, asserts tree
```

## 3. Schema-to-types pipelines (JS/TS)

| Source | Tool options | Output | Notes |
| --- | --- | --- | --- |
| OpenAPI 3.x | `openapi-typescript` (types only), `orval`/`openapi-fetch` (client), `openapi-generator` (multi-language) | `types.ts`, typed fetch client | generate from a committed spec, never from a running server |
| GraphQL | `graphql-codegen` (client and server presets) | typed hooks/operations | schema + documents; persisted queries optional |
| JSON Schema | `json-schema-to-typescript`, `typebox-codegen` | interfaces | pairs with runtime validator generation |
| Runtime validators | `zod`/`valibot` built from schemas, or schema-first with `typebox` | validators + inferred types | single source: schema first, types inferred |
| SQL/ORM | `kysely-codegen`, `prisma generate`, `drizzle-kit` | typed query clients | regenerate after every migration in CI |

Minimal OpenAPI pipeline:

```bash
# package.json scripts (contracts package)
"gen:api": "openapi-typescript ../../specs/billing.yaml -o src/generated/billing.ts"
"check:api": "pnpm gen:api && git diff --exit-code src/generated"
```

```ts
// src/index.ts
export type { paths, components } from "./generated/billing";
```

Rules:

- The spec is committed in the repo (`specs/`, `packages/contracts/`). Generating from a URL or live service makes builds non-reproducible and offline-hostile.
- Generated types are consumed through the contracts package; apps never import generated files across package boundaries.
- Validate at runtime too: types alone do not protect against a non-conforming server. See the typescript pack's validator guidance and [02-structure-boundaries](./02-structure-boundaries.md).

## 4. Protobuf and Buf

Buf replaces hand-rolled `protoc` invocations with lint, breaking-change detection, and generation from a config.

```yaml
# buf.yaml
version: v2
modules:
  - path: proto
lint:
  use: [STANDARD]
breaking:
  use: [FILE]
```

```yaml
# buf.gen.yaml
version: v2
managed:
  enabled: true
plugins:
  - local: protoc-gen-es
    out: gen/es
    opt: target=ts
  - local: protoc-gen-connect-es
    out: gen/es
    opt: target=ts
```

```bash
buf lint
buf breaking --against "https://github.com/acme/apis.git#branch=main"   # verified remote or git ref
buf generate
```

Rules:

- One proto module per domain, one generated package per language inside the monorepo (`packages/gen/es`, `gen/go`, `gen/py`).
- Pin plugin versions (`protoc-gen-es@<range>`); plugin output changes are breaking for consumers.
- `buf breaking` runs in CI against the default branch; it is the cheapest API-compatibility gate available.
- Never edit `gen/` output; regenerate and commit, or regenerate in CI (choose one policy, below).
- Field numbers, enums, and services follow proto evolution rules: never reuse removed field numbers, reserve them.

## 5. Where generated code lives

| Pattern | Layout | Use when |
| --- | --- | --- |
| Package per artifact | `packages/contracts-billing/src/generated` | schemas are products consumed by multiple apps |
| Co-located | `apps/api/src/generated` | single consumer; keep it out of shared packages |
| Language-split | `gen/es`, `gen/go`, `gen/py` | polyglot protobuf |
| Tool-owned | `tools/<tool>/generated` | repo automation, not runtime code |

Decisions that must be explicit:

- Generated packages are `private` unless they are published deliberately.
- Generated code is excluded from lint/format but included in type-check and build.
- CODEOWNERS maps generated directories to the spec owner, not to whoever ran the generator.
- API docs are generated from the same source; do not hand-write types documentation.

## 6. Commit or generate on build

| Policy | Pros | Cons | Best when |
| --- | --- | --- | --- |
| Commit generated output | builds work without generators; reviewable diffs; caching simple | noisy diffs; merge conflicts in generated files | external API clients, published packages |
| Generate in CI/build | clean diffs; always current | every build needs generators; cache keys must include specs and plugin versions | internal-only code, fast pipelines |

Either way:

- A CI job runs the generator and fails if the committed output differs (`git diff --exit-code`), or builds from scratch and tests the generated surface.
- Spec and generator versions are task inputs; if they are not, caches will lie.
- On spec change, the PR includes generated diff plus a changeset when the generated package is published.

## 7. Determinism requirements

- Pin generator and plugin versions exactly; never `@latest` in a build step.
- Sort maps/keys and imports in templates; byte-identical output across runs and machines.
- Do not embed timestamps, git hashes, or absolute paths in generated headers, or cache and diff checks will always fail.
- Generate with the same toolchain version as CI; a generator upgrade is a deliberate change with a diff to review.
- Use a stable file header: `// Code generated by <tool> <version> from <source>. DO NOT EDIT.`

## 8. Drift detection in CI

```yaml
- name: Verify generated code
  run: |
    pnpm run gen:all
    git diff --exit-code -- '*/generated/*' 'gen/'
```

Additional checks:

- Schemas referenced by code must exist (no orphan specs, no unreferenced generated packages).
- Every generated package builds and type-checks; broken generated code must fail fast, not at app build time.
- Buf breaking checks for proto; OpenAPI diff tools (`oasdiff`) for REST compatibility.
- Track "generated at" provenance in release notes when consumers depend on it.

## 9. Anti-patterns

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| Hand-editing generated files | changes lost on next run | edit the template/spec |
| Generating from a live server | non-reproducible builds, CI flakiness | commit the spec |
| Unpinned generator version | surprise diffs and breakage | pin exactly, upgrade deliberately |
| Spec outside the repo | consumers cannot build offline | vendor the spec in `specs/` |
| Generated output not in cache inputs/outputs | stale or skipped codegen | declare inputs and outputs |
| Multiple generators for one artifact | conflicting output | one source, one generator |
| No drift check | committed output silently stale | `git diff --exit-code` in CI |
| Generated code linted/formatted | churn in every PR | ignore generated paths |

## Checklist

- [ ] Every generated artifact has one committed source of truth.
- [ ] Generators are the only path to new packages; generator tests exist.
- [ ] Generator and plugin versions are pinned; output is deterministic.
- [ ] Generated code has a `DO NOT EDIT` header and is excluded from lint/format.
- [ ] CI regenerates and fails on drift, or builds the generated surface in every run.
- [ ] Specs and generator config are declared task inputs.
- [ ] API compatibility gates (Buf breaking, OpenAPI diff) run on spec changes.
- [ ] CODEOWNERS covers specs and generated directories.

Related: [02-structure-boundaries](./02-structure-boundaries.md) for where generated packages live, [04-shared-config](./04-shared-config.md) for exports and build wiring, [05-caching-ci](./05-caching-ci.md) for correct codegen caching.
