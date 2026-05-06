#!/usr/bin/env node

import { execSync } from "node:child_process";
import { existsSync, mkdirSync, cpSync, readFileSync, writeFileSync, chmodSync, readdirSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";

const REPO = "https://github.com/GabrielRenno/hone.git";
const BRANCH = "main";
const tmp = join(tmpdir(), `hone-${Date.now()}`);
const cwd = process.cwd();

const cyan = (s) => `\x1b[36m[hone]\x1b[0m ${s}`;
const green = (s) => `\x1b[32m[hone]\x1b[0m ${s}`;
const yellow = (s) => `\x1b[33m[hone]\x1b[0m ${s}`;
const red = (s) => `\x1b[31m[hone]\x1b[0m ${s}`;

function cleanup() {
  try { rmSync(tmp, { recursive: true, force: true }); } catch {}
}

process.on("exit", cleanup);
process.on("SIGINT", () => { cleanup(); process.exit(1); });

// --- Clone ---

console.log(cyan("Downloading Hone..."));
try {
  execSync(`git clone --depth 1 --branch ${BRANCH} ${REPO} ${tmp}`, { stdio: "ignore" });
} catch {
  console.error(red("Failed to clone Hone repo. Is git installed?"));
  process.exit(1);
}

// --- Copy directories ---

const dirs = [".claude", "docs", "evals"];

for (const dir of dirs) {
  const src = join(tmp, dir);
  const dest = join(cwd, dir);

  if (existsSync(dest)) {
    console.log(yellow(`${dir}/ already exists — merging (won't overwrite).`));
    copyNewFiles(src, dest, dir);
  } else {
    cpSync(src, dest, { recursive: true });
    console.log(green(`Copied ${dir}/`));
  }
}

// --- Copy CLAUDE.md ---

const claudeMd = join(cwd, "CLAUDE.md");
if (existsSync(claudeMd)) {
  const templatePath = join(cwd, "CLAUDE.md.hone-template");
  cpSync(join(tmp, "CLAUDE.md"), templatePath);
  console.log(yellow("CLAUDE.md already exists — saved template as CLAUDE.md.hone-template"));
} else {
  cpSync(join(tmp, "CLAUDE.md"), claudeMd);
  console.log(green("Copied CLAUDE.md"));
}

// --- GitHub workflow ---

const workflowDir = join(cwd, ".github", "workflows");
const evalYml = join(workflowDir, "eval.yml");
mkdirSync(workflowDir, { recursive: true });

if (!existsSync(evalYml)) {
  cpSync(join(tmp, ".github", "workflows", "eval.yml"), evalYml);
  console.log(green("Copied .github/workflows/eval.yml"));
} else {
  console.log(yellow(".github/workflows/eval.yml already exists — skipped."));
}

// --- Make hooks executable ---

const hooksDir = join(cwd, ".claude", "hooks");
if (existsSync(hooksDir)) {
  for (const file of readdirSync(hooksDir)) {
    if (file.endsWith(".sh")) {
      chmodSync(join(hooksDir, file), 0o755);
    }
  }
  console.log(green("Made hooks executable."));
}

// --- Merge .gitignore ---

const destIgnore = join(cwd, ".gitignore");
const srcIgnore = join(tmp, ".gitignore");

if (existsSync(destIgnore)) {
  const existing = readFileSync(destIgnore, "utf-8");
  const incoming = readFileSync(srcIgnore, "utf-8");
  const existingLines = new Set(existing.split("\n").map((l) => l.trim()));
  const toAdd = incoming.split("\n").filter((l) => l.trim() && !existingLines.has(l.trim()));
  if (toAdd.length > 0) {
    writeFileSync(destIgnore, existing.trimEnd() + "\n" + toAdd.join("\n") + "\n");
  }
  console.log(green("Merged .gitignore entries."));
} else {
  cpSync(srcIgnore, destIgnore);
  console.log(green("Copied .gitignore"));
}

// --- Done ---

console.log("");
console.log(green("Hone installed."));
console.log("");
console.log(cyan("Next steps:"));
console.log("  1. Edit CLAUDE.md — replace <project-name> with your project name");
console.log("  2. Trim the Stack section to match your actual stack");
console.log("  3. Verify toolchain: python3, git, ruff, mypy, pytest");
console.log("  4. Open Claude Code and run:  /plan add a /healthz endpoint");
console.log("");
console.log(cyan("Docs: https://github.com/GabrielRenno/hone"));

// --- Helpers ---

function copyNewFiles(src, dest, prefix) {
  for (const entry of readdirSync(src, { withFileTypes: true })) {
    const srcPath = join(src, entry.name);
    const destPath = join(dest, entry.name);
    const relPath = join(prefix, entry.name);

    if (entry.isDirectory()) {
      if (!existsSync(destPath)) {
        cpSync(srcPath, destPath, { recursive: true });
        console.log(green(`  Added ${relPath}/`));
      } else {
        copyNewFiles(srcPath, destPath, relPath);
      }
    } else {
      if (!existsSync(destPath)) {
        mkdirSync(dirname(destPath), { recursive: true });
        cpSync(srcPath, destPath);
        console.log(green(`  Added ${relPath}`));
      }
    }
  }
}
