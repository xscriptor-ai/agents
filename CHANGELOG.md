# Changelog

## 2026-07-16 — Claude Code Conversion

- **205 agents, 21 skills, 8 commands** translated from OpenCode to Claude Code and installed to `~/.claude/`
- Agent frontmatter: added `name`, removed `mode`/`temperature`/`aggregates`, mapped `permission` → `tools`, mapped colors to Claude Code's 8-name palette
- `permission:` → `tools:`: 18 read-only agents get explicit `tools` list; 187 agents inherit session tools
- Skills: dropped `version:`, prefixed senior skills (`senior-python`, etc.), rewrote `load skill` references
- Commands: prefixed with `x-` to avoid collision with native `/review`; replaced `agent:`+`subtask:` with explicit delegation instructions
- Converter written: `tools/xscriptor-convert.py` (idempotent, requires `pyyaml`)
- Validation: 0 invalid files, 0 duplicate names, 0 collisions with native agents/skills

## 2026-07-12 — Agents Upload & Commands

- Added **8 OpenCode commands**: `/arch`, `/audit`, `/deploy`, `/design`, `/docs`, `/refactor`, `/review`, `/test`
- Added **24 consolidated senior agents**: cloud-native, compliance, content, data-ml, game-dev, GitHub, Go, JVM, mobile, Python, Rust, security, systems, testing, TypeScript, web
- Added **18 deep-reference skills** for senior agents
- Optimized existing agents (`code-reviewer`, `security-auditor`, `consent-anonymization`, `data-mapping`, `privacy-dsar-ccpa`, `digital-forensics`)
- Removed `forensic-analysis` agent (consolidated into `digital-forensics`)
- Updated npm packages and install scripts
- Added `senior/README.md` and `commands/README.md`

## 2026-06-03 — Mega Agents & Docs Update

- Added **7 mega agents**: `mega-app-dev`, `mega-compliance`, `mega-devsecops`, `mega-ir`, `mega-migration`, `mega-research-action`, `mega-security-assessment`
- Added **research agents**: `cultural-researcher`, `literary-researcher`, `mega-researcher`, `psychology-researcher`, `research-lead`, `scientific-researcher`, `security-researcher`, `tech-researcher`, `trends-researcher`
- Added **GitHub agents**: `actions-workflow`, `admin-security`, `api-automation`
- Added `powershell-specialist` agent
- Updated documentation and npm package

### 2026-06-03 — Agent Upload

- Added **4 VS Code extension agents**: `vscode-debug-extension`, `vscode-language-extension`, `vscode-lsp-extension`, `vscode-ui-extension`
- Added **markdown agents**: `markdown-architect`, `markdown-editor`, `markdown-html`
- Added `agent-creator` agent
- Updated `content-editor`, `content-reviser`, `api-docs`, `db-migrator`, `docs-writer`, `performance-analyzer`, `refactor-agent`, `test-writer`

### 2026-06-02 — Specialized Agents

- Added **30 specialized agents** across 13 new domains:
  - Automotive security, aviation security
  - Blockchain security (DeFi, smart contracts)
  - Cloud (multi-cloud networking, serverless security)
  - Compliance (FedRAMP, GRC automation, HIPAA, PCI DSS, SOX ITGC)
  - Embedded/IoT security
  - Hardware security
  - Mainframe security
  - Maritime/energy security
  - Medical device security
  - Mobile app security
  - Observability (log management, OpenTelemetry)
  - Physical security
  - Privacy engineering (consent, data mapping, DSAR)
  - AI/ML security
  - Blue team (SOC automation, threat intel, vuln management)

## 2026-05-31 — NPM Packages & Skills

- Published **4 npm packages**:
  - `@xscriptor/ai-agents` — main agent installer
  - `skill-devx` — DX skill package
  - `skill-samurai` — Samurai skill package
  - `skill-xscriptor` — Xscriptor skill package
- Added `LICENSE` files
- Moved skills from `agents/skills` to standalone `skills/` directory
- Created `skills/README.md`

### 2026-05-31 — Structure Refactor

- Reorganized agents under categorized directories (cloud, compliance, content, data-ml, embedded, game-dev, general)
- Updated `README.md` with new structure
- Restructured and re-added agents after refactor

### 2026-05-31 — Standard Scripts

- Added **8 utility scripts**:
  - `scripts/audit/check-permissions.sh`
  - `scripts/backup/backup-agents.sh`
  - `scripts/diff/diff-agents.sh`
  - `scripts/docs/build-docs.sh`
  - `scripts/generate/generate-agent.sh`
  - `scripts/stats/agent-stats.py`, `agent-stats.sh`
  - `scripts/validate/validate-agents.sh`

## 2026-05-30 — Initial Release

- Repository initialization
- Added **28 base agents**: cloud (5), compliance (2), content (4), data-ml (4), embedded (2), game-dev (2), general (9)
- Created initial `README.md` and `agents/README.md`
- Initial project structure with `agents/` directory
