#!/usr/bin/env node
// @xscriptor/skill-devx - Install the DevX development skill.
// Usage: npx @xscriptor/skill-devx [--opencode|--anthropic|--dry-run]
import { existsSync, mkdirSync, copyFileSync, readdirSync, statSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PKG_DIR = join(__dirname, "..");
const REPO_DIR = join(PKG_DIR, "..", "..");

function dstPath(target) {
  const home = process.env.HOME || process.env.USERPROFILE || "";
  if (target === "anthropic") return join(home, ".claude", "skills", "devx");
  const xdg = process.env.XDG_CONFIG_HOME || join(home, ".config");
  return join(xdg, "opencode", "skills", "devx");
}

function srcPath() {
  const p = join(PKG_DIR, "skills", "web", "dev", "devx");
  const r = join(REPO_DIR, "skills", "web", "dev", "devx", "devx");
  return existsSync(p) ? p : r;
}

function copyDir(s, d, dry) {
  let c = 0;
  for (const e of readdirSync(s)) {
    const sp = join(s, e), dp = join(d, e);
    if (statSync(sp).isDirectory()) { if (!dry) mkdirSync(dp, { recursive: true }); c += copyDir(sp, dp, dry); }
    else if (e.endsWith(".md") || e.endsWith(".json")) {
      if (!dry) { mkdirSync(d, { recursive: true }); copyFileSync(sp, dp); }
      console.log(`  ${dry ? "-" : "+"} ${e}`); c++;
    }
  }
  return c;
}

const args = process.argv.slice(2);
const target = args.includes("--anthropic") ? "anthropic" : "opencode";
const dryRun = args.includes("--dry-run");
const src = srcPath();
const dst = dstPath(target);

if (!existsSync(src)) { console.error("Skill source not found"); process.exit(1); }

console.log(`==> @xscriptor/skill-devx -> ${dst}\n`);
const c = copyDir(src, dst, dryRun);
console.log(dryRun ? `\n==> Would install ${c} files` : `\n==> ${c} files installed`);
