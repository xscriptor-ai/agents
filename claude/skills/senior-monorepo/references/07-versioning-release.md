# Versioning and Release

> Scope: Changesets, fixed vs linked vs independent versioning, release trains, canary/snapshot releases, publishing, and changelogs.

Versioning is a policy decision that must be written down before the first release. The tooling is easy; deciding what "a version" means in your repository is the hard part.

## 1. Choose a version policy

| Policy | Behavior | Use when | Failure mode |
| --- | --- | --- | --- |
| Fixed | one version for a group; any change bumps all members | packages ship as one product (component library suite) | unrelated packages churn versions |
| Linked | versions kept equal among members, bumped only when a member changes | tightly coupled suites with occasional independent releases | coordination overhead |
| Independent | each package versions on its own changes | unrelated libraries with distinct audiences | version skew and dependency range chaos |
| None (private) | never versioned, consumed via workspace | internal apps, config packages | accidental publishing |

Typical split in one repo:

- Product apps: not versioned (or versioned by deployment tag), built and deployed, never published.
- Internal libraries: `private: true`, no release.
- Published libraries: changesets with an explicit group policy.

Document the policy in `CONTRIBUTING.md` and encode it in `.changeset/config.json`. Never leave the policy implicit; contributors will guess differently.

## 2. Changesets workflow

Changesets is the default for JS/TS monorepos. Verify the current CLI and config schema upstream.

```jsonc
// .changeset/config.json
{
  "$schema": "https://unpkg.com/@changesets/config/schema.json",
  "changelog": "@changesets/cli/changelog",
  "commit": false,
  "access": "public",
  "baseBranch": "main",
  "updateInternalDependencies": "patch",
  "ignore": ["@acme/web", "@acme/config-*", "@acme/e2e"],
  "fixed": [["@acme/ui", "@acme/icons", "@acme/tokens"]],
  "linked": [],
  "snapshot": { "useCalculatedVersion": false, "prereleaseTemplate": "{tag}-{datetime}" }
}
```

Workflow:

1. Every PR that changes a published package adds a changeset (`pnpm changeset`): affected packages, bump type, human-written summary.
2. CI enforces a changeset on publishable changes (bot check or `changeset status --since=origin/main`).
3. A "Version Packages" PR accumulates changesets; merging it runs `changeset version` (bump versions, update internal ranges, write changelogs).
4. Merging the version PR triggers `changeset publish` (or a separate release job) with provenance.
5. `changeset tag` creates git tags for each released package; keep tag naming consistent (`@acme/ui@1.4.0` or `v1.4.0` for a fixed group).

Rules:

- Changeset summaries are end-user changelog content. "Fix bug" is not a summary; write what changed and why it matters.
- Do not hand-edit `CHANGELOG.md`; generated changelogs are the record.
- `updateInternalDependencies` controls how internal ranges are rewritten; `patch` is the sane default, `minor`/`major` only if the policy requires it.
- The version PR is reviewed like code: unexpected packages in the diff mean the changeset was wrong.
- Private packages are ignored; if a private package changes, no release is needed, but its dependents may still need a bump through the dependency graph.

## 3. Release trains

A release train is a scheduled, batched release instead of continuous publishing.

| Model | Cadence | Best for |
| --- | --- | --- |
| Continuous | every merge to main | infrastructure libraries, fast-consuming teams |
| Scheduled train | weekly/biweekly | enterprise consumers needing predictable upgrades |
| Milestone train | per product milestone | coordinated product releases |
| Freeze windows | release candidate -> GA | regulated or certification-bound products |

Practice:

- Announce the train schedule and the cutoff. After cutoff, changes go to the next train.
- Tag the train and publish release notes that aggregate the included changesets.
- Keep a hotfix lane: critical fixes branch from the release tag, get a patch version, and merge back.
- Version the train itself only if consumers consume the train; otherwise version packages and describe the train in release notes.

## 4. Canary, snapshot, and prerelease

| Mechanism | Command shape | Purpose |
| --- | --- | --- |
| Canary | `changeset version --snapshot canary` + `changeset publish --tag canary` | per-commit testing by early adopters |
| Snapshot | `changeset version --snapshot` | CI-only verification builds, not published |
| Prerelease | `changeset pre enter next` -> versions are `1.1.0-next.0` | staged majors/minors with a shared suffix |
| Dist-tag | `npm publish --tag next` | channel routing without version churn |

Rules:

- Prerelease mode is entered and exited deliberately; forgetting `changeset pre exit` strands the repo in prerelease versions.
- Canary versions are disposable; never make a canary a dependency range in a shipped package.
- Publish canaries with a dedicated dist-tag (`canary`, `next`) and never overwrite `latest`.
- Test the consumed artifact: install the canary into a real app in CI before promoting.

## 5. Publishing

For npm (and equivalents on other registries):

```yaml
# release.yml (sketch)
permissions:
  contents: write
  id-token: write            # OIDC for provenance/trusted publishing
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<pinned-sha>
        with: { fetch-depth: 0 }
      - uses: pnpm/action-setup@<pinned-sha>
      - uses: actions/setup-node@<pinned-sha>
        with:
          node-version-file: .nvmrc
          registry-url: https://registry.npmjs.org
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm build --filter "...[origin/main]"
      - run: pnpm exec changeset publish
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

Requirements and practices:

- Enable provenance/trusted publishing via OIDC where the registry supports it; long-lived tokens are the fallback, scoped to publish-only.
- `publishConfig.access` and `publishConfig.registry` per package; scoped private registries configured in `.npmrc` (never commit tokens).
- Build before publish in the same job; never publish whatever happens to be in `dist/`.
- Validate packages before upload: `npm pack --dry-run`, `publint`, `attw`; fail the release on findings.
- Publish from a clean checkout of the tag/commit; no local uncommitted state.
- Releases are idempotent when retried: Changesets skips versions already on the registry. Prefer retrying over manual `npm publish`.
- Git tags, GitHub/GitLab releases, and changelogs are created from the same run so they cannot diverge.
- For fixed groups, publish in dependency order; the tool handles topological order, but verify after policy changes.

## 6. Changelogs and release notes

- Per-package `CHANGELOG.md` generated from changesets; one root release note for humans that links the packages.
- Changelog entries follow the bump semantics: breaking changes first, then features, then fixes.
- Link PRs/issues in changeset summaries where the tooling allows; traceability is the point.
- Deprecations get their own section and a removal timeline.
- Security fixes: coordinate disclosure, publish patch versions, and note affected ranges clearly without revealing exploit detail before the embargo ends.

## 7. Alternatives to Changesets

| Tool | Model | Consider when |
| --- | --- | --- |
| `nx release` | conventional commits or changesets + publish + changelog | already on Nx and want one tool |
| Lerna | legacy fixed/independent versioning + publish | maintaining an existing Lerna repo |
| semantic-release | fully automated from commit messages | single-package or very disciplined conventional commits |
| release-please | manifest-based release PRs | GitHub-centric, language-agnostic |
| Custom scripts | anything | you accept owning edge cases (dist-tags, provenance, prereleases) |

Pick one versioning mechanism. Two mechanisms in one repo guarantee conflicting changelogs and double publishes.

## 8. Failure modes

| Failure | Cause | Prevention |
| --- | --- | --- |
| Version skew across packages | independent policy without discipline | linked/fixed groups for coupled packages; drift checks |
| Duplicate publish attempts | non-idempotent custom scripts | use changeset publish; retry |
| Published package missing files | `files`/`exports` misconfigured | `npm pack --dry-run` gate |
| Wrong internal range after publish | `workspace:*` policy mismatch | test install from registry in CI |
| Changelog says nothing | bad changeset summaries | review changesets like code |
| Prerelease leaked to `latest` | missing `--tag` | explicit dist-tags, protected release env |
| Stale lockfile in release | install not frozen | frozen install before publish |
| Broken release because a dependency was unpublished | no dependency graph awareness | publish in topo order, verify with a consumer smoke test |

## 9. Anti-patterns

- Editing `package.json` versions by hand.
- One repo-wide version bump that publishes unchanged packages.
- Skipping changesets for "small" changes to published APIs.
- Publishing from a developer machine or a non-protected branch.
- Using `latest` for prereleases or canaries.
- Changelogs generated from raw commit messages with no editing.
- Two release tools racing on the same packages.
- No smoke test that installs the published artifact.

## Checklist

- [ ] Version policy documented per package group (fixed, linked, independent, private).
- [ ] Changesets configured with `ignore`, `fixed`/`linked`, and internal dependency update policy.
- [ ] CI requires a changeset for publishable changes and validates `changeset status`.
- [ ] Version PR reviewed; release job publishes from a clean checkout with provenance.
- [ ] Pre/post release validation: pack, publint, attw, consumer smoke test.
- [ ] Canary/prerelease channels use dedicated dist-tags; `latest` is protected.
- [ ] Tags, changelogs, and registry state come from one automated run.
- [ ] Hotfix path exists and is documented.

Related: [02-structure-boundaries](./02-structure-boundaries.md) for API stability, [03-dependencies](./03-dependencies.md) for internal ranges, [09-governance-metrics](./09-governance-metrics.md) for drift and release health.
