#!/usr/bin/env bash
# Hone installer — drops the harness into the current project.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/GabrielRenno/hone/main/install.sh | bash
#
# What it does:
#   1. Clones the Hone repo into a temp directory
#   2. Copies .claude/, docs/, evals/, CLAUDE.md, .github/ into the current directory
#   3. Makes hooks executable
#   4. Merges .gitignore entries
#   5. Cleans up
#
# What it does NOT do:
#   - Overwrite existing files without asking
#   - Install dependencies (you still need ruff, mypy, pytest on your PATH)
#   - Modify your existing CLAUDE.md if one exists

set -euo pipefail

REPO="https://github.com/GabrielRenno/hone.git"
BRANCH="main"
TMPDIR=$(mktemp -d)
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

info()  { echo -e "${CYAN}[hone]${NC} $1"; }
ok()    { echo -e "${GREEN}[hone]${NC} $1"; }
warn()  { echo -e "${YELLOW}[hone]${NC} $1"; }
fail()  { echo -e "${RED}[hone]${NC} $1"; exit 1; }

# --- Preflight checks ---

if ! command -v git &> /dev/null; then
  fail "git is required but not found on PATH."
fi

if [[ ! -d ".git" ]] && [[ ! -f "pyproject.toml" ]] && [[ ! -f "package.json" ]]; then
  warn "This doesn't look like a project root (no .git, pyproject.toml, or package.json)."
  read -rp "Install here anyway? [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    info "Aborted."
    exit 0
  fi
fi

# --- Clone ---

info "Downloading Hone..."
git clone --depth 1 --branch "$BRANCH" "$REPO" "$TMPDIR" 2>/dev/null || fail "Failed to clone Hone repo."

# --- Copy harness files ---

DIRS=(".claude" "docs" "evals")
FILES=("CLAUDE.md")

for dir in "${DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    warn "$dir/ already exists — merging (won't overwrite existing files)."
    # Copy without overwriting existing files
    find "$TMPDIR/$dir" -type f | while read -r src; do
      rel="${src#$TMPDIR/}"
      if [[ ! -f "$rel" ]]; then
        mkdir -p "$(dirname "$rel")"
        cp "$src" "$rel"
      else
        warn "  Skipped $rel (already exists)"
      fi
    done
  else
    cp -r "$TMPDIR/$dir" .
    ok "Copied $dir/"
  fi
done

for file in "${FILES[@]}"; do
  if [[ -f "$file" ]]; then
    warn "$file already exists — skipped. See $TMPDIR/$file for the template."
    cp "$TMPDIR/$file" "$file.hone-template"
    info "  Saved template as $file.hone-template for reference."
  else
    cp "$TMPDIR/$file" .
    ok "Copied $file"
  fi
done

# --- GitHub workflow (optional) ---

if [[ ! -d ".github/workflows" ]]; then
  mkdir -p .github/workflows
fi

if [[ ! -f ".github/workflows/eval.yml" ]]; then
  cp "$TMPDIR/.github/workflows/eval.yml" .github/workflows/
  ok "Copied .github/workflows/eval.yml"
else
  warn ".github/workflows/eval.yml already exists — skipped."
fi

# --- Make hooks executable ---

if [[ -d ".claude/hooks" ]]; then
  chmod +x .claude/hooks/*.sh 2>/dev/null || true
  ok "Made hooks executable."
fi

# --- Merge .gitignore ---

if [[ -f ".gitignore" ]]; then
  while IFS= read -r line; do
    if [[ -n "$line" ]] && ! grep -qxF "$line" .gitignore 2>/dev/null; then
      echo "$line" >> .gitignore
    fi
  done < "$TMPDIR/.gitignore"
  ok "Merged .gitignore entries."
else
  cp "$TMPDIR/.gitignore" .
  ok "Copied .gitignore"
fi

# --- Summary ---

echo ""
ok "Hone installed."
echo ""
info "Next steps:"
echo "  1. Edit CLAUDE.md — replace <project-name> with your project name"
echo "  2. Trim the Stack section to match your actual stack"
echo "  3. Verify toolchain: python3, git, ruff, mypy, pytest"
echo "  4. Open Claude Code and run:  /plan add a /healthz endpoint"
echo ""
info "Docs: https://github.com/GabrielRenno/hone"
