#!/bin/bash
# Incubator OS Plugin Installer (macOS / Linux)
#
# Usage:
#   curl -fsSL https://incubator-os.com/install.sh?t=<token> | bash

set -e

INSTALL_TOKEN="__INSTALL_TOKEN_PLACEHOLDER__"
API_BASE="${INCUBATOR_OS_API_BASE:-https://incubator-os.com}"
INC_OS_DIR="$HOME/.incubator-os"
WORKSPACE_BASE="$HOME/incubator"

# Colors
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

echo ""
echo -e "  ${BOLD}Incubator OS Plugin Installer${RESET}"
echo ""

if [ -z "$INSTALL_TOKEN" ] || [ "$INSTALL_TOKEN" = "__INSTALL_TOKEN_PLACEHOLDER__" ]; then
  echo -e "  ${RED}No install token provided. Use the URL Austin sent you.${RESET}"
  exit 1
fi

# ── Detect OS ──────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *)      echo -e "  ${RED}Unsupported OS: $OS${RESET}"; exit 1 ;;
esac

# ── Install Homebrew (macOS) if missing ────────────────────────────
if [ "$PLATFORM" = "macos" ] && ! command -v brew >/dev/null 2>&1; then
  echo -e "  ${BOLD}Installing Homebrew...${RESET}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
fi

# ── Install dependencies ───────────────────────────────────────────
install_pkg() {
  local pkg="$1"
  if [ "$PLATFORM" = "macos" ]; then
    brew install "$pkg"
  else
    sudo apt-get install -y "$pkg"
  fi
}

ensure_cmd() {
  local cmd="$1"
  local pkg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "  ${BOLD}Installing $pkg...${RESET}"
    install_pkg "$pkg"
  fi
}

if [ "$PLATFORM" = "linux" ]; then
  sudo apt-get update -y
fi

ensure_cmd git git
ensure_cmd curl curl
ensure_cmd node node

if ! command -v claude >/dev/null 2>&1; then
  echo -e "  ${BOLD}Installing Claude Code...${RESET}"
  npm install -g @anthropic-ai/claude-code
fi

# ── Partial-state recovery: skip credential fetch if auth.json valid ──
SKIP_FETCH=false
if [ -f "$INC_OS_DIR/auth.json" ] && [ -f "$INC_OS_DIR/token" ]; then
  EXISTING_CID=$(node -e "try{console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).client_id||'')}catch{}" "$INC_OS_DIR/auth.json" 2>/dev/null)
  if [ -n "$EXISTING_CID" ]; then
    echo -e "  ${DIM}Found existing install state, skipping credential fetch.${RESET}"
    NAME=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).name||'')" "$INC_OS_DIR/auth.json" 2>/dev/null)
    EMAIL=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).email||'')" "$INC_OS_DIR/auth.json" 2>/dev/null)
    AUTH_TOKEN=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).token||'')" "$INC_OS_DIR/auth.json" 2>/dev/null)
    CLIENT_ID="$EXISTING_CID"
    REPO_URL=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).repo_url||'')" "$INC_OS_DIR/auth.json" 2>/dev/null)
    PAT=$(cat "$INC_OS_DIR/token")
    SKIP_FETCH=true
  fi
fi

if [ "$SKIP_FETCH" = false ]; then

# ── Fetch credentials ──────────────────────────────────────────────
echo -e "  ${BOLD}Fetching your workspace credentials...${RESET}"

RESP=$(curl -fsSL "${API_BASE}/api/incubator-os/install/${INSTALL_TOKEN}" || echo '{"error":"network"}')
ERR=$(echo "$RESP" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf-8'));if(d.error)console.log(d.error)}catch{}" 2>/dev/null)

if [ -n "$ERR" ]; then
  echo -e "  ${RED}Install failed: $ERR${RESET}"
  echo -e "  ${DIM}Contact Austin for a fresh install URL.${RESET}"
  exit 1
fi

NAME=$(echo "$RESP" | node -e "console.log(JSON.parse(require('fs').readFileSync(0,'utf-8')).name)")
EMAIL=$(echo "$RESP" | node -e "console.log(JSON.parse(require('fs').readFileSync(0,'utf-8')).email)")
REPO_URL=$(echo "$RESP" | node -e "console.log(JSON.parse(require('fs').readFileSync(0,'utf-8')).repo_url)")
PAT=$(echo "$RESP" | node -e "console.log(JSON.parse(require('fs').readFileSync(0,'utf-8')).pat)")
AUTH_TOKEN=$(echo "$RESP" | node -e "console.log(JSON.parse(require('fs').readFileSync(0,'utf-8')).auth_token)")
CLIENT_ID=$(echo "$RESP" | node -e "console.log(JSON.parse(require('fs').readFileSync(0,'utf-8')).client_id)")

fi  # end SKIP_FETCH

REPO_NAME=$(basename "$REPO_URL" .git)

# ── Write auth files ───────────────────────────────────────────────
mkdir -p "$INC_OS_DIR"
chmod 700 "$INC_OS_DIR"

# Build auth.json via node (JSON.stringify guarantees correct escaping)
node -e '
const fs = require("fs");
const [path, tok, em, nm, cid, api, repo] = process.argv.slice(1);
fs.writeFileSync(path, JSON.stringify({ token: tok, email: em, name: nm, client_id: cid, api_base: api, repo_url: repo }, null, 2) + "\n");
' "$INC_OS_DIR/auth.json" "$AUTH_TOKEN" "$EMAIL" "$NAME" "$CLIENT_ID" "$API_BASE" "$REPO_URL"
chmod 600 "$INC_OS_DIR/auth.json"

printf '%s' "$PAT" > "$INC_OS_DIR/token"
chmod 600 "$INC_OS_DIR/token"

# ── Configure git credential helper (URL-scoped, NOT global) ───────
HELPER_SCRIPT="$INC_OS_DIR/credential-helper.sh"
cat > "$HELPER_SCRIPT" <<'HELPER'
#!/bin/sh
# Reads the PAT for HTTPS auth to github.com/austinmarchese/*
[ "$1" = "get" ] || exit 0
echo "username=austinmarchese"
echo "password=$(cat "$HOME/.incubator-os/token")"
HELPER
chmod +x "$HELPER_SCRIPT"

git config --global "credential.https://github.com/austinmarchese.helper" "$HELPER_SCRIPT"

# ── Clone repo ─────────────────────────────────────────────────────
mkdir -p "$WORKSPACE_BASE"
WORKSPACE_DIR="$WORKSPACE_BASE/$REPO_NAME"

if [ -d "$WORKSPACE_DIR/.git" ]; then
  echo -e "  ${DIM}Workspace already cloned at $WORKSPACE_DIR, pulling latest...${RESET}"
  git -C "$WORKSPACE_DIR" pull --ff-only || true
else
  echo -e "  ${BOLD}Cloning workspace to $WORKSPACE_DIR...${RESET}"
  git clone "$REPO_URL" "$WORKSPACE_DIR"
fi

# (Commit identity is set per-repo AFTER clone — see below)
git -C "$WORKSPACE_DIR" config user.name "$NAME"
git -C "$WORKSPACE_DIR" config user.email "$EMAIL"

# ── Desktop alias (macOS only, best-effort) ────────────────────────
if [ "$PLATFORM" = "macos" ]; then
  osascript -e "tell application \"Finder\" to make alias file to (POSIX file \"$WORKSPACE_DIR\") at desktop" >/dev/null 2>&1 || true
fi

# ── Install plugin ─────────────────────────────────────────────────
echo -e "  ${BOLD}Installing the Incubator OS plugin...${RESET}"

# Idempotent re-runs: remove existing entries first
claude plugin marketplace remove incubator-os 2>/dev/null || true

claude plugin marketplace add austinmarchese/incubator-os-plugin
claude plugin install incubator-os@incubator-os

# ── Ensure CLAUDE.md exists ────────────────────────────────────────
# Block content is injected by sweep.mjs on first SessionStart (one source of truth).
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$CLAUDE_MD")"
touch "$CLAUDE_MD"

# ── Done ───────────────────────────────────────────────────────────
echo ""
echo -e "  ${GREEN}Install complete${RESET}"
echo ""
echo -e "  ${BOLD}Next step:${RESET}"
echo -e "  Open Claude Code at this folder:"
echo ""
echo -e "    ${BOLD}$WORKSPACE_DIR${RESET}"
echo ""
echo -e "  Try: ${BOLD}/inc-os:update${RESET}"
echo ""
echo -e "  ${DIM}Note: on first session, Claude Code may show a one-time approval${RESET}"
echo -e "  ${DIM}prompt for the Incubator OS plugin. Approve it when it appears.${RESET}"
echo ""
