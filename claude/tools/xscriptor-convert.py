#!/usr/bin/env python3
"""Convert xscriptor-ai/agents + xscriptor-ai/skills (OpenCode format) -> Claude Code format in ~/.claude/.

Sources:
  --src         agents repo root (needs agents/ and senior/agents/)
  --skills-src  skills repo root (needs senior/ and web-fullstack/; content/ optional)
                default: sibling ../skills of --src, else the same --src (legacy monorepo)
"""
import os, re, sys, shutil, pathlib
import yaml

def _arg(flag, default):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default

SRC = pathlib.Path(_arg("--src", "./ai")).expanduser().resolve()
SKILLS_ARG = _arg("--skills-src", None)
DST = pathlib.Path(_arg("--dst", "~/.claude")).expanduser()
DRY = "--dry" in sys.argv

if not (SRC / "agents").is_dir():
    sys.exit(f"error: {SRC} does not look like a clone of github.com/xscriptor-ai/agents")

def find_skills_src():
    if SKILLS_ARG:
        return pathlib.Path(SKILLS_ARG).expanduser().resolve()
    sibling = SRC.parent / "skills"
    if (sibling / "senior").is_dir() or (sibling / "web-fullstack").is_dir():
        return sibling
    return SRC

SKILLS_SRC = find_skills_src()
if not ((SKILLS_SRC / "senior").is_dir() or (SKILLS_SRC / "web-fullstack").is_dir()):
    sys.exit(f"error: {SKILLS_SRC} does not contain the skills repo layout "
             "(senior/ + web-fullstack/); pass --skills-src /path/to/xscriptor-ai/skills")

COLOR_MAP = {
    "error": "red", "warning": "orange", "info": "blue", "success": "green",
    "primary": "blue", "accent": "purple", "secondary": "cyan",
}

# Senior skills install as "senior-<name>" in Claude Code so they do not clash
# with user skills. OpenCode references them by their bare installed name.
SENIOR_SKILL_NAMES = {
    "api-design", "architecture", "cloud", "deployment", "go", "java-kotlin",
    "mobile", "monorepo", "observability", "performance", "python", "rust",
    "secure-coding", "security", "systems", "testing", "typescript", "web",
}


def rewrite_skill_refs(body):
    """Map skill references in an agent/skill body to Claude Code names.

    OpenCode uses the bare installed name ("skill web"); Claude uses the
    prefixed name ("skill senior-web"). The legacy "skill senior/web" form is
    still accepted.
    """
    body = re.sub(r"\bskill senior/([a-z0-9-]+)", r"skill senior-\1", body)

    def _map(m):
        name = m.group(1)
        return f"skill senior-{name}" if name in SENIOR_SKILL_NAMES else m.group(0)

    return re.sub(r"\bskill `?([a-z0-9-]+)`?", _map, body)

report = {"agents": [], "skills": [], "commands": [], "notes": []}


def split_fm(text):
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        return None, text
    return yaml.safe_load(m.group(1)) or {}, m.group(2)


def dump(fm, body):
    return "---\n" + yaml.dump(fm, sort_keys=False, allow_unicode=True,
                               default_flow_style=False).strip() + "\n---\n" + body


def perm_val(p):
    """OpenCode permission value -> 'allow'|'ask'|'deny'.

    For a pattern map the default ("*") decides; specific patterns are
    reported separately by bash_allows().
    """
    if isinstance(p, str):
        return p
    if isinstance(p, dict):
        return p.get("*", "ask")
    return "deny"


def bash_allows(p):
    """Bash command patterns explicitly allowed, e.g. ['grep *', 'npm *']."""
    if isinstance(p, dict):
        return sorted(k for k, v in p.items() if v == "allow" and k != "*")
    return []


def convert_agent(path, rel):
    fm, body = split_fm(path.read_text())
    if fm is None:
        return None
    name = path.stem
    new = {"name": name, "description": str(fm.get("description", "")).strip()}

    perm = fm.get("permission", {}) or {}
    edit = perm_val(perm.get("edit", "deny"))
    bash = perm_val(perm.get("bash", "deny"))
    read_only = edit == "deny" and bash == "deny"

    if read_only:
        tools = ["Read", "Glob", "Grep"]
        if bash_allows(perm.get("bash")):
            tools.append("Bash")
        if perm_val(perm.get("webfetch", "deny")) != "deny":
            tools += ["WebFetch", "WebSearch"]
        if perm_val(perm.get("task", "deny")) != "deny":
            tools.append("Task")
        new["tools"] = ", ".join(tools)
        kind = "read-only (tools pinned)"
    else:
        kind = "inherits all tools"

    c = fm.get("color")
    if isinstance(c, str) and c in COLOR_MAP:
        new["color"] = COLOR_MAP[c]

    # senior agents reference skills as "senior/python" -> installed dir is "senior-python"
    body = rewrite_skill_refs(body)

    dropped = [k for k in fm if k not in ("description", "permission", "color", "mode")]
    report["agents"].append((rel, name, kind, dropped))

    out = DST / "agents" / "xscriptor" / rel
    if not DRY:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(dump(new, body))
    return name


def convert_skill(skill_dir, dst_name):
    sk = skill_dir / "SKILL.md"
    fm, body = split_fm(sk.read_text())
    fm = fm or {}
    new = {"name": dst_name, "description": str(fm.get("description", "")).strip()}
    at = fm.get("allowed-tools")
    if at:
        new["allowed-tools"] = ", ".join(at) if isinstance(at, list) else str(at)
    body = rewrite_skill_refs(body)

    out = DST / "skills" / dst_name
    if not DRY:
        out.mkdir(parents=True, exist_ok=True)
        (out / "SKILL.md").write_text(dump(new, body))
        refs = skill_dir / "references"
        if refs.is_dir():
            shutil.copytree(refs, out / "references", dirs_exist_ok=True)
    report["skills"].append((dst_name, str(fm.get("version", "-")),
                             len(list((skill_dir / "references").glob("*"))) if (skill_dir / "references").is_dir() else 0))


def convert_command(path):
    fm, body = split_fm(path.read_text())
    fm = fm or {}
    name = "x-" + path.stem
    new = {"description": str(fm.get("description", "")).strip(),
           "argument-hint": "[target]"}
    agent = fm.get("agent")
    if agent:
        body = (f"Delegate this task to the `{agent}` subagent via the Task tool, "
                f"passing along the context below.\n\n" + body.lstrip())
        new["allowed-tools"] = "Task, Read, Glob, Grep, Bash(git diff:*), Bash(git status:*)"
    out = DST / "commands" / f"{name}.md"
    if not DRY:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(dump(new, body))
    report["commands"].append((f"/{name}", agent or "-"))


def main():
    names = {}
    for base in ("agents", "senior/agents"):
        root = SRC / base
        for p in sorted(root.rglob("*.md")):
            if p.name == "README.md":
                continue
            rel = p.relative_to(root)
            rel = pathlib.Path(("senior" if base.startswith("senior") else "specialized")) / rel
            n = convert_agent(p, rel)
            if n:
                names.setdefault(n, []).append(str(rel))

    dups = {k: v for k, v in names.items() if len(v) > 1}
    if dups:
        report["notes"].append(f"DUPLICATE AGENT NAMES: {dups}")

    for p in sorted((SKILLS_SRC / "senior").glob("*/SKILL.md")):
        convert_skill(p.parent, "senior-" + p.parent.name)
    for p in sorted((SKILLS_SRC / "web-fullstack").rglob("SKILL.md")):
        convert_skill(p.parent, p.parent.name)
    content_dir = SKILLS_SRC / "content"
    if content_dir.is_dir():
        for p in sorted(content_dir.rglob("SKILL.md")):
            convert_skill(p.parent, p.parent.name)

    commands_src = SKILLS_SRC / "commands"
    if commands_src.is_dir():
        for p in sorted(commands_src.glob("*.md")):
            if p.name == "README.md":
                continue
            convert_command(p)

    print(f"agents: {len(report['agents'])} | skills: {len(report['skills'])} | commands: {len(report['commands'])}")
    ro = [a for a in report["agents"] if "read-only" in a[2]]
    print(f"read-only agents: {len(ro)} | inherit-all: {len(report['agents']) - len(ro)}")
    alldropped = sorted({d for a in report["agents"] for d in a[3]})
    print("dropped frontmatter keys:", alldropped)
    for n in report["notes"]:
        print("NOTE:", n)
    print("skills:", ", ".join(s[0] for s in report["skills"]))
    print("commands:", ", ".join(c[0] for c in report["commands"]))


main()
