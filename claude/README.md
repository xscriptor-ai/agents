# `claude/` — build for Claude Code

This directory is the `agents/`, `senior/`, `skills/` and `commands/` **translated to the
Claude Code format**. It is an **exact mirror of `~/.claude/`**: installation is a plain copy.

```
claude/
├── agents/xscriptor/
│   ├── specialized/<group>/<agent>.md    181 specialist agents
│   └── senior/<ecosystem>/<agent>.md     24 senior agents
├── skills/
│   ├── senior-<topic>/SKILL.md           18 reference skills
│   └── {xscriptor,devx,samurai}/SKILL.md    3 project skills (+ references/)
├── commands/x-<name>.md                   8 slash commands
└── tools/xscriptor-convert.py               generator of this directory
```

## Install

```bash
# Global (user)
cp -r claude/agents claude/skills claude/commands ~/.claude/

# Per-project only
cp -r claude/agents claude/skills claude/commands /path/to/project/.claude/
```

Uninstall agents: `rm -rf ~/.claude/agents/xscriptor` (everything hangs off that, nothing else is touched).

## Regenerate

`claude/` is not edited by hand — it is generated from the OpenCode sources in the repo:

```bash
python3 claude/tools/xscriptor-convert.py --src . --dst ./claude --dry   # preview
python3 claude/tools/xscriptor-convert.py --src . --dst ./claude         # apply
```

Idempotent. Requires `pyyaml`. If you change an agent, edit it in `agents/` or `senior/agents/`
and re-run the converter.

## Why this directory exists

The repo is written in **OpenCode format**. The installer `opencode/scripts/install-agents.sh` (and the
npm package) have an `--anthropic` flag, but they only **copy files without translating
frontmatter**, and that frontmatter is invalid in Claude Code: it lacks the required `name` field,
and `mode`, `temperature` and the `permission:` block do not exist in its schema.

## OpenCode → Claude Code differences

### Agents

| OpenCode | Claude Code | Action |
|---|---|---|
| *(does not exist)* | `name` | **Added** from filename (required) |
| `description` | `description` | Same |
| `mode: subagent` | — | Removed (implicit) |
| `temperature: 0.1` | — | **Removed: not supported** |
| `permission: {...}` | `tools` | Translated (see below) |
| `color: error\|info\|…` | `color: red\|blue\|…` | Mapped to 8-name palette |
| `aggregates` | — | Removed (mega-only, no equivalent) |

Color mapping: `error→red`, `warning→orange`, `info→blue`, `success→green`, `primary→blue`,
`accent→purple`, `secondary→cyan`. Hex values (`#3178C6`…) are dropped — Claude Code only accepts those 8 names.

Agents are discovered recursively and their identity comes **only** from the `name` field, not
the path. The `xscriptor/` subfolder exists so they can be uninstalled with a single `rm` and
won't mix with user-defined agents.

### `permission:` → `tools:` (the most impactful change)

OpenCode defines permissions per tool **and per command pattern**:

```yaml
permission:
  edit: allow
  bash:
    "*": ask
    "pip *": allow
```

Claude Code does not support pattern-based rules in agent frontmatter — only a flat `tools` list.
Applied rule:

- **18 read-only agents** (`edit: deny` and `bash` with default `deny`) → `tools: Read, Glob, Grep`
  (+ `Bash` if specific patterns were allowed, + `WebFetch, WebSearch` if `webfetch` was
  not denied, + `Task` if `task` was allowed). Their write-safety guarantee is preserved.
- **187 remaining agents** → `tools` is omitted, they inherit all session tools.

**Consequence:** those 187 lose fine-grained bash restrictions (e.g. "only `pip *` without
asking"). There is no silent execution — the rules from `~/.claude/settings.json` still apply —
but to get that behavior back you must declare it in `permissions.allow` in `settings.json`,
not in the agent.

### Skills

- `version:` removed — **not supported** by Claude Code.
- `allowed-tools` normalized to comma-separated string.
- `senior/skills/` entries are prefixed: `python` → **`senior-python`**. In `~/.claude/skills/` the
  directory name *is* the skill name and is global; `python`, `web`, `security` or
  `testing` would collide with user skills and be ambiguous in the `/` menu.
- That is why the converter **rewrites body references**: senior agents say
  `load skill senior/python`, which becomes `load skill senior-python`. Without this step they would
  point to non-existent skills.
- `references/` folders from `xscriptor`, `devx` and `samurai` are copied as-is.

> `xscriptor`, `devx` and `samurai` document **specific projects**, not general knowledge.
> They fit better in each repo's `.claude/skills/` than globally.

### Commands

- **`x-` prefix**: `/review` → `/x-review`, etc. Claude Code ships with `/review`, `/code-review` and
  `/security-review` natively; without the prefix there would be a collision with `/review`.
- `agent: <name>` + `subtask: true` do not exist in Claude Code. They are replaced by an explicit
  instruction at the start of the body (*"Delegate this task to the `X` subagent via the Task tool"*)
  plus `allowed-tools: Task, Read, Glob, Grep, Bash(git diff:*), Bash(git status:*)`.
- Added `argument-hint: [target]`.
- The interpolation `` !`git diff` `` **is compatible** and stays intact. It requires
  `disableSkillShellExecution` to not be active in settings.

Commands: `/x-arch`, `/x-audit`, `/x-deploy`, `/x-design`, `/x-docs`, `/x-refactor`, `/x-review`, `/x-test`.

## Validation

205 agents, 21 skills, 8 commands. All valid YAML frontmatter, no duplicate agent names, and no
collisions with Claude Code's native agents or skills.
