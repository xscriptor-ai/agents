# Xscriptor Agents

Ready-to-use **AI agents** for [OpenCode](https://opencode.ai) and [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview). This is the base repo: it holds all agent definitions, the generated Claude Code mirror, the converter, and links to the companion repos.

## Contents

- `agents/` — 181 specialized agents (33 groups)
- `senior/agents/` — 24 consolidated senior agents (16 ecosystems)
- `claude/` — generated Claude Code mirror of all agents/skills/commands (see `claude/tools/xscriptor-convert.py`)

## Companion Repos

| Repo | Content | Size |
|---|---|---|
| [skills](https://github.com/xscriptor-ai/skills) | Project skills + deep-reference skills + slash commands | 3 + 18 + 8 |
| [scripts](https://github.com/xscriptor-ai/scripts) | Utility scripts (install, validate, generate, ...) | 8 scripts |
| [packages](https://github.com/xscriptor-ai/packages) | npm packages (`@xscriptor/ai-agents` + skill packages) | 4 packages |

## Install

```bash
# Everything, via npm (no clone)
npx @xscriptor/ai-agents

# Clone this repo
git clone https://github.com/xscriptor-ai/agents.git
cd agents
# Installer lives in the scripts repo
bash <(curl -fsSL https://raw.githubusercontent.com/xscriptor-ai/scripts/main/install-agents.sh)
```

## License

MIT
