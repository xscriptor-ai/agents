# Changelog

## 2026-07-16

### Conversion from OpenCode to Claude Code

- **205 agents**, **21 skills**, **8 commands** translated and installed to `~/.claude/`
- **Agent frontmatter**: added `name`, removed `mode`/`temperature`/`aggregates`, mapped `permission` → `tools`, mapped colors to Claude Code's 8-name palette
- **`permission:` → `tools:`**: 18 read-only agents get explicit `tools` list; 187 agents inherit session tools (loss of per-pattern bash rules)
- **Skills**: dropped `version:`, prefixed senior skills (`senior-python`, etc.), rewrote `load skill` references in bodies
- **Commands**: prefixed with `x-` to avoid collision with native `/review`; replaced `agent:`+`subtask:` with explicit delegation instructions
- **Converter** written: `tools/xscriptor-convert.py` (idempotent, requires `pyyaml`)
- **Validation**: 0 invalid files, 0 duplicate names, 0 collisions with native agents/skills
