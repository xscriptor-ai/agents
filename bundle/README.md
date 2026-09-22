# bundle — skill-enabled agent set

Curated copies of the agents that map cleanly to one of our senior skills.
Every file here is a copy of the original (`agents/…`, `agents/…`) with
two differences:

1. A **Skills** callout is injected right after the frontmatter, telling the
   agent which `<name>` skill to load for current, deep patterns.
2. Targeted **2026 currency fixes** were applied (version bumps, renamed tools,
   deprecated flags/APIs found in the audit).

The originals are **not modified or moved**. This folder is a ready-to-install,
skill-aware set.

## Usage

Install the whole set (each file keeps its group path):

```bash
# OpenCode
cp -r bundle/. ~/.config/opencode/agents/

# Claude Code (frontmatter must be converted first; see agents/claude/tools)
```

Or cherry-pick a group, e.g. `bundle/web/backend/`.

## Skill reference convention

The callout reads:

```
> **Skills.** Load skill `go` for current (2026) deep
> patterns: idioms, decision tables, pitfalls and checklists. This agent
> defines the role and workflow; defer to the skill(s) for specifics.
```

Skill ids are the **bare installed names** (`go`, `python`, `web`, `security`,
...). The folders in `xscriptor-ai/skills/senior/<name>/` declare `name: <name>`
and install flat, so the OpenCode `skill` tool resolves `<name>` directly. In
Claude Code the converter prefixes them (`senior-<name>`), so the `claude/`
mirror references `senior-go`, `senior-python`, etc.

## Mapping (group → skills)

| Agent path | Skills |
|---|---|
| `languages/go-developer` | `go` |
| `languages/{java,kotlin}-developer` | `java-kotlin` |
| `languages/python-developer` | `python` |
| `languages/rust-developer`, `embedded/embedded-rust-developer` | `rust` |
| `languages/typescript-developer`, `languages/vscode-*` | `typescript` |
| `mobile/{android,ios,flutter,react-native}-developer` | `mobile` |
| `mobile/mobile-app-secure-coding` | `mobile`, `secure-coding` |
| `mobile/mobile-malware-analysis` | `security` |
| `embedded/c-cpp-developer` | `systems`, `secure-coding` |
| `embedded/iot-ot-security` | `security`, `systems` |
| `cloud/*` | `cloud` (`serverless-security` also `security`) |
| `systems/*` | `systems` (`network-security`, `offensive-shell-scripting` also `security`; `container-orchestration` also `cloud`) |
| `observability/*` | `observability` |
| `testing/*` | `testing` (`performance-testing-specialist` also `performance`) |
| `graphql/graphql-specialist` | `api-design` |
| `web/architecture/*` | `architecture` (`zero-trust-architect` also `security`) |
| `web/backend/api-designer` | `api-design` |
| `web/backend/{caching,database}-specialist` | `performance` |
| `web/backend/database-security` | `security`, `secure-coding` |
| `web/backend/devops-specialist` | `deployment`, `cloud` |
| `web/backend/{message-queue,microservices-architect}` | `architecture` |
| `web/frontend/{angular,nextjs,react,vue}-*` | `web`, `typescript` |
| `web/frontend/frontend-performance` | `performance`, `web` |
| `web/frontend/{accessibility,css-ui}-specialist` | `web` |
| `web/security/secure-coding` | `secure-coding` |
| `web/security/{appsec-engineer,web-security-auditor}` | `security`, `secure-coding` |
| `web/security/*` (rest) | `security` |
| `security/**` | `security` (`security/mobile-pentest/*` also `mobile`) |
| `{automotive,aviation,blockchain,hardware,mainframe,maritime,medical,physical,telecom}-security/*` | `security` |
| `general/{code-reviewer,dependency-auditor}` | `secure-coding` |
| `general/security-auditor` | `security` |
| `general/test-writer` | `testing` |
| `general/performance-analyzer` | `performance` |
| `general/db-migrator` | `deployment` |
| `general/api-docs` | `api-design` |
| `mega/mega-app-dev` | `architecture`, `web`, `api-design` |
| `mega/mega-devsecops` | `security`, `secure-coding`, `deployment` |
| `mega/mega-ir`, `mega/mega-security-assessment` | `security` |
| `mega/mega-migration` | `architecture`, `deployment` |
| `go` | `go` |
| `java-kotlin` | `java-kotlin` |
| `mobile` | `mobile` |
| `rust` | `rust` |
| `testing` | `testing` |
| `systems` | `systems`, `security` |
| `security` | `security`, `secure-coding` |
| `typescript` | `typescript`, `web` |
| `web` | `web` |
| `cloud/senior-cloud-native` | `cloud`, `deployment`, `observability` |
| `cloud/senior-devops` | `deployment`, `cloud`, `security` |
| `python` | `python` |
| `data-ml/senior-data-platform` | `python`, `observability`, `deployment` |

159 agents total.

## Currency fixes applied (79 replacements)

Examples of what was corrected in the copies: Go 1.22+ → 1.24+, Java 21+ → 25+,
Spring Boot 3.x → 4.x, postgres:16 → 18, Kotlin 2.0 → 2.2, Android target API 34
→ 36, iOS 17+ → 18+, Reanimated 3 → 4, Flutter 3.24/Dart 3.5 → 3.35/3.9,
`probe-run` → `probe-rs run`, C++20/23 → C++23/26, UE 5.4/docs URL, Unity 6
label, Istio `…/v1beta1` → `v1`, Angular v17 → v20 + zoneless API, `forwardRef`
era React Router v6 → v7, Nuxt 3 → 4, Node 18 → 22, `datetime.utcnow()` →
`datetime.now(timezone.utc)`, CVSS v3.1 → v4.0, `crackmapexec` → NetExec,
`hcxpcaptool` → `hcxpcapngtool`, `tfsec`/`zap-cli` → Trivy / ZAP Automation,
`Get-WmiObject` → `Get-CimInstance`, `kextstat` → `kmutil`, `semconv/v1.20` →
v1.30, `td-agent` → `fluent`, etc.

## Audit leftovers (not in this folder)

These groups have **no matching senior skill**, so they were not copied. They
still contain outdated content worth fixing in the originals:

- `compliance/*`: PCI DSS 4.0 → 4.0.1 (future reqs mandatory since 2025-03-31);
  FedRAMP JAB P-ATO retired → agency authorization / FedRAMP 20x, Rev4 → NIST
  800-53 Rev5 baselines, FIPS 140-2 → 140-3; HIPAA caps inflation-adjusted
  (~$71k / ~$2.1M); GRC: NIST CSF 2.0 (6 functions/22 categories), ISO
  27001:2022 clauses, `datetime.utcnow()`; GDPR add AI Act/NIS2/DORA/Data Act/EU-US DPF.
- `content/*`: `bleach` → `nh3`, Django `rendered_preview.allow_tags` removed,
  marked `sanitize`/`headerIds`/`mangle` removed, Pygments CDN 2.17 → 2.19,
  Python 3.12 → 3.14, `broken-link-checker` → lychee.
- `data-ml/*`: `tritonserver:23.12` → current 25.x, TorchServe archived → Triton/
  KServe/vLLM, CML deprecated, Terraform-only → add OpenTofu.
- `game-dev/*`: Unity 6 label (6000.x), Zenject/Extenject → VContainer/Reflex,
  `docs.unrealengine.com` → `dev.epicgames.com/documentation`, UE 5.4 → 5.6+.
- `github/*`: Node 18 in matrices → 22/24, `node20` action runtime,
  `secret_scanning.yml` custom-pattern format unsupported, `gh issue develop`
  flag casing.
- `privacy-engineering/*`: TCF 2.0 vs 2.2 mismatch, `datetime.utcnow()`,
  hardcoded 2024 dates.
- `general` researchers/docs: DSM-5 → 5-TR, literature date ranges rolled
  forward, CVSS v4 metric key, `agent-creator` path
  `packages/ai-agents/` → `packages/packages/ai-agents`, research templates dated 2024.
- Senior `compliance`, `content`, `game-dev`, `github` agents: no skill in the
  set (nearest is `security`); still fix the version issues above.

Additional findings not mechanically applied (need a human edit): OWASP Top 10
2021 vs 2025 wording, SLSA level numbering, GitHub Actions pinning, OpenVPN
`data-ciphers`, Snort 2 → 3, WSUS → Autopatch/Intune, macOS `airport`/`kextstat`
nuances, Fluentd paths, Playwright `networkidle`, and various prose claims.

Repository is emoji-free: the only emoji in the originals
(`agents/compliance/pci-dss-specialist.md`, `agents/content/markdown-editor.md`
and their `claude/` mirrors) were replaced with plain text (`OK:`/`BAD:` and
`Preview`).
