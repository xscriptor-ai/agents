#!/usr/bin/env node
// @xscriptor/ai-agents - Install AI agents, skills, and commands for OpenCode and Claude Code.
// Usage: npx @xscriptor/ai-agents [--all|--agents|--senior|--skills|--commands] [--opencode|--anthropic|--project]
import { existsSync, mkdirSync, copyFileSync, readdirSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PKG_DIR = join(__dirname, "..");
const REPO_DIR = join(PKG_DIR, "..", "..", "..");
const REPO_AGENTS = join(REPO_DIR, "agents");
const REPO_SENIOR = join(REPO_DIR, "senior/agents");
const REPO_SKILLS = join(REPO_DIR, "skills");
const REPO_SENIOR_SKILLS = join(REPO_DIR, "senior/skills");
const REPO_COMMANDS = join(REPO_DIR, "commands");

const HELP = `
Usage: npx @xscriptor/ai-agents [options]

Selection (default: --all):
  --all               Install everything: agents + senior + skills + commands
  --agents            Specialized agents only
  --senior            Senior agents only
  --skills            Skills only (project + senior)
  --commands          Commands only
  --groups LIST       Comma-separated groups (e.g. general,web/security)

Target (default: --opencode):
  --opencode          Install to ~/.config/opencode/
  --anthropic         Install to ~/.claude/
  --project           Install to .opencode/ (current dir)

Other:
  --dry-run           Preview without copying
  --list              List available groups
  --help              Show this help

Examples:
  npx @xscriptor/ai-agents
  npx @xscriptor/ai-agents --senior
  npx @xscriptor/ai-agents --skills
  npx @xscriptor/ai-agents --commands
  npx @xscriptor/ai-agents --groups general,languages
`;

const AGENT_GROUPS = [
  "general", "languages", "web/security", "web/architecture", "web/frontend", "web/backend",
  "mobile", "data-ml", "cloud", "testing", "content", "observability", "compliance",
  "security/recon", "security/web-pentest", "security/mobile-pentest", "security/desktop",
  "security/red-team", "security/blue-team", "graphql", "embedded", "game-dev",
];

const SENIOR_GROUPS = [
  "cloud", "compliance", "content", "data-ml", "game-dev", "github", "go", "java-kotlin",
  "mobile", "python", "rust", "security", "systems", "testing", "typescript", "web",
];

const SENIOR_SKILLS = [
  "api-design", "architecture", "cloud", "deployment", "go", "java-kotlin", "mobile",
  "monorepo", "observability", "performance", "python", "rust", "secure-coding", "security",
  "systems", "testing", "typescript", "web",
];

const SKILL_ROUTES = [
  { name: "xscriptor", src: "web/literature/xscriptor" },
  { name: "devx", src: "web/dev/devx/devx" },
  { name: "samurai", src: "web/cybersec/samurai" },
];

function dstPath(target, sub) {
  const home = process.env.HOME || process.env.USERPROFILE || "";
  if (target === "anthropic") return join(home, ".claude", sub);
  if (target === "project") return join(process.cwd(), ".opencode", sub);
  const xdg = process.env.XDG_CONFIG_HOME || join(home, ".config");
  return join(xdg, "opencode", sub);
}

function copySkill(name, srcDir, dstDir, dryRun) {
  const skillSrc = join(srcDir, name);
  const skillDst = join(dstDir, name);
  const skillFile = join(skillSrc, "SKILL.md");
  if (!existsSync(skillFile)) return 0;
  mkdirSync(skillDst, { recursive: true });
  if (!dryRun) copyFileSync(skillFile, join(skillDst, "SKILL.md"));
  console.log(`    ${dryRun ? "-" : "+"} ${name}/SKILL.md`);
  let count = 1;
  const refsSrc = join(skillSrc, "references");
  if (existsSync(refsSrc)) {
    const refsDst = join(skillDst, "references");
    mkdirSync(refsDst, { recursive: true });
    const refItems = readdirSync(refsSrc);
    for (const item of refItems) {
      const s = join(refsSrc, item);
      const d = join(refsDst, item);
      if (!dryRun) copyFileSync(s, d);
      console.log(`      ${dryRun ? "-" : "+"} ${item}`);
      count++;
    }
  }
  return count;
}

function main() {
  const args = process.argv.slice(2);
  if (args.includes("--help")) { console.log(HELP); return; }

  const mode = args.includes("--senior") ? "senior"
    : args.includes("--skills") ? "skills"
    : args.includes("--commands") ? "commands"
    : args.includes("--agents") ? "agents"
    : args.includes("--groups") ? "groups"
    : "all";

  const target = args.includes("--anthropic") ? "anthropic"
    : args.includes("--project") ? "project"
    : "opencode";

  const dryRun = args.includes("--dry-run");

  if (args.includes("--list")) {
    console.log("Available agent groups:");
    for (const g of AGENT_GROUPS) {
      const d = join(REPO_AGENTS, g);
      if (existsSync(d)) {
        const c = readdirSync(d).filter(f => f.endsWith(".md")).length;
        console.log(`  ${g.padEnd(25)} ${c} agents`);
      }
    }
    console.log("\nSenior agent groups:");
    for (const g of SENIOR_GROUPS) {
      const d = join(REPO_SENIOR, g);
      if (existsSync(d)) {
        const c = readdirSync(d).filter(f => f.endsWith(".md")).length;
        console.log(`  ${g.padEnd(25)} ${c} agents`);
      }
    }
    console.log(`\nSenior skills: ${SENIOR_SKILLS.length}`);
    if (existsSync(REPO_COMMANDS)) {
      const cmds = readdirSync(REPO_COMMANDS).filter(f => f.endsWith(".md")).length;
      console.log(`Commands: ${cmds}`);
    }
    return;
  }

  const agentsDst = dstPath(target, "agents");
  const skillsDst = dstPath(target, "skills");
  const commandsDst = dstPath(target, "commands");
  let total = 0;

  const groupsArg = args.indexOf("--groups");
  const selectedGroups = groupsArg >= 0 ? args[groupsArg + 1].split(",") : AGENT_GROUPS;

  console.log(`==> @xscriptor/ai-agents (mode: ${mode})`);
  console.log(`    → ${agentsDst}`);
  console.log(`    → ${skillsDst}`);
  console.log(`    → ${commandsDst}\n`);

  const doAgents = mode === "all" || mode === "agents" || mode === "groups";
  const doSenior = mode === "all" || mode === "senior";
  const doSkills = mode === "all" || mode === "skills";
  const doCommands = mode === "all" || mode === "commands";

  if (doAgents) {
    const groups = mode === "groups" ? selectedGroups : AGENT_GROUPS;
    console.log("  [Specialized Agents]");
    for (const group of groups) {
      const gs = join(REPO_AGENTS, group);
      if (!existsSync(gs)) { console.log(`    [SKIP] ${group}`); continue; }
      const files = readdirSync(gs).filter(f => f.endsWith(".md"));
      if (files.length === 0) { console.log(`    [SKIP] ${group} (empty)`); continue; }
      console.log(`    [${group}]`);
      for (const f of files) {
        if (!dryRun) {
          mkdirSync(agentsDst, { recursive: true });
          copyFileSync(join(gs, f), join(agentsDst, f));
        }
        console.log(`      ${dryRun ? "-" : "+"} ${f}`);
        total++;
      }
    }
  }

  if (doSenior) {
    console.log("  [Senior Agents]");
    for (const group of SENIOR_GROUPS) {
      const gs = join(REPO_SENIOR, group);
      if (!existsSync(gs)) { console.log(`    [SKIP] ${group}`); continue; }
      const files = readdirSync(gs).filter(f => f.endsWith(".md"));
      if (files.length === 0) { console.log(`    [SKIP] ${group} (empty)`); continue; }
      console.log(`    [${group}]`);
      for (const f of files) {
        if (!dryRun) {
          mkdirSync(agentsDst, { recursive: true });
          copyFileSync(join(gs, f), join(agentsDst, f));
        }
        console.log(`      ${dryRun ? "-" : "+"} ${f}`);
        total++;
      }
    }
  }

  if (doSkills) {
    console.log("  [Skills]");
    for (const sk of SKILL_ROUTES) {
      const src = join(REPO_SKILLS, sk.src);
      console.log(`    [${sk.name}]`);
      total += copySkill(sk.name, join(REPO_SKILLS, sk.src, ".."), skillsDst, dryRun);
    }
    console.log("    [senior]");
    for (const sk of SENIOR_SKILLS) {
      const cnt = copySkill(sk, REPO_SENIOR_SKILLS, skillsDst, dryRun);
      if (cnt > 0) total += cnt;
    }
  }

  if (doCommands) {
    console.log("  [Commands]");
    if (existsSync(REPO_COMMANDS)) {
      const files = readdirSync(REPO_COMMANDS).filter(f => f.endsWith(".md"));
      for (const f of files) {
        if (!dryRun) {
          mkdirSync(commandsDst, { recursive: true });
          copyFileSync(join(REPO_COMMANDS, f), join(commandsDst, f));
        }
        console.log(`    ${dryRun ? "-" : "+"} ${f}`);
        total++;
      }
    }
  }

  console.log(dryRun
    ? `\n==> Would install ${total} items`
    : `\n==> ${total} items installed`
  );
}

main();
