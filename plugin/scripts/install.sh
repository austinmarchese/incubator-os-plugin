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

# Brand colors (theincubator.xyz)
BRAND_ORANGE='\033[38;2;166;68;34m'      # #a64422
BRAND_ACCENT='\033[38;2;204;119;90m'     # #cc775a
BRAND_CREAM='\033[38;2;243;237;226m'     # #f3ede2
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo ""
echo -e "${BRAND_ORANGE}  ╭─────────────────────────────────────────╮${RESET}"
echo -e "${BRAND_ORANGE}  │  Incubator OS — Your AI Workspace        │${RESET}"
echo -e "${BRAND_ORANGE}  ╰─────────────────────────────────────────╯${RESET}"
echo ""

if [ -z "$INSTALL_TOKEN" ] || [ "$INSTALL_TOKEN" = "__INSTALL_TOKEN_PLACEHOLDER__" ]; then
  echo -e "  ${RED}No install token provided. Use the URL Austin sent you.${RESET}"
  exit 1
fi

# ── [1/4] Dependencies ─────────────────────────────────────────────
echo -e "${BRAND_ACCENT}  [1/4]${RESET}${BOLD} Installing dependencies...${RESET}"
echo ""

# ── Detect OS ──────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *)      echo -e "  ${RED}Unsupported OS: $OS${RESET}"; exit 1 ;;
esac

# ── Install Homebrew (macOS) if missing ────────────────────────────
if [ "$PLATFORM" = "macos" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
    echo -e "  ${GREEN}✓ Homebrew (installed)${RESET}"
  else
    echo -e "  ${GREEN}✓ Homebrew (already installed)${RESET}"
  fi
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

if [ "$PLATFORM" = "linux" ]; then
  sudo apt-get update -y
fi

for item in "git:git" "curl:curl" "node:node"; do
  cmd="${item%%:*}"
  pkg="${item##*:}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    install_pkg "$pkg"
    echo -e "  ${GREEN}✓ $pkg (installed)${RESET}"
  else
    echo -e "  ${GREEN}✓ $pkg (already installed)${RESET}"
  fi
done

# ── Ingest dependencies (best-effort; non-fatal) ───────────────────
# yt-dlp: used by scripts/fetch_youtube_transcript.py for title/channel metadata
if ! command -v yt-dlp >/dev/null 2>&1; then
  install_pkg yt-dlp 2>/dev/null \
    && echo -e "  ${GREEN}✓ yt-dlp (installed)${RESET}" \
    || echo -e "  ${YELLOW}! yt-dlp not available — YouTube transcript metadata will fall back to video ID only${RESET}"
else
  echo -e "  ${GREEN}✓ yt-dlp (already installed)${RESET}"
fi

# youtube-transcript-api: Python package used by scripts/fetch_youtube_transcript.py
PY=""
command -v python3 >/dev/null 2>&1 && PY=python3
if [ -n "$PY" ]; then
  if "$PY" -c "import youtube_transcript_api" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓ youtube-transcript-api (already installed)${RESET}"
  else
    "$PY" -m pip install --quiet youtube-transcript-api 2>/dev/null \
      && echo -e "  ${GREEN}✓ youtube-transcript-api (installed)${RESET}" \
      || echo -e "  ${YELLOW}! youtube-transcript-api not installed — run: pip install youtube-transcript-api${RESET}"
  fi
else
  echo -e "  ${YELLOW}! python3 not found — YouTube ingest requires manual setup (see scripts/fetch_youtube_transcript.py)${RESET}"
fi

if ! command -v claude >/dev/null 2>&1; then
  npm install -g @anthropic-ai/claude-code
  echo -e "  ${GREEN}✓ Claude Code (installed)${RESET}"
else
  echo -e "  ${GREEN}✓ Claude Code (already installed)${RESET}"
fi

echo ""

# ── [2/4] Workspace credentials ────────────────────────────────────
echo -e "${BRAND_ACCENT}  [2/4]${RESET}${BOLD} Setting up your workspace credentials...${RESET}"
echo ""

# ── Partial-state recovery: skip credential fetch if auth.json valid ──
SKIP_FETCH=false
if [ -f "$INC_OS_DIR/auth.json" ] && [ -f "$INC_OS_DIR/token" ]; then
  EXISTING_CID=$(node -e "try{console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).client_id||'')}catch{}" "$INC_OS_DIR/auth.json" 2>/dev/null)
  if [ -n "$EXISTING_CID" ]; then
    NAME=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).name||'')" "$INC_OS_DIR/auth.json" 2>/dev/null)
    EMAIL=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).email||'')" "$INC_OS_DIR/auth.json" 2>/dev/null)
    AUTH_TOKEN=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).token||'')" "$INC_OS_DIR/auth.json" 2>/dev/null)
    CLIENT_ID="$EXISTING_CID"
    REPO_URL=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).repo_url||'')" "$INC_OS_DIR/auth.json" 2>/dev/null)
    PAT=$(cat "$INC_OS_DIR/token")
    SKIP_FETCH=true
    echo -e "  ${GREEN}✓ Fetched credentials for $NAME (cached)${RESET}"
  fi
fi

if [ "$SKIP_FETCH" = false ]; then

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

  echo -e "  ${GREEN}✓ Fetched credentials for $NAME${RESET}"

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
echo -e "  ${GREEN}✓ Wrote ~/.incubator-os/auth.json (chmod 600)${RESET}"

printf '%s' "$PAT" > "$INC_OS_DIR/token"
chmod 600 "$INC_OS_DIR/token"
echo -e "  ${GREEN}✓ Wrote ~/.incubator-os/token (chmod 600)${RESET}"

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
echo -e "  ${GREEN}✓ Configured URL-scoped git credential helper for github.com/austinmarchese/*${RESET}"

# ── Set commit identity ────────────────────────────────────────────
# (Set globally here; will also be set per-repo after clone)
echo -e "  ${GREEN}✓ Set commit identity on workspace: $NAME <$EMAIL>${RESET}"

echo ""

# ── [3/4] Clone workspace ──────────────────────────────────────────
echo -e "${BRAND_ACCENT}  [3/4]${RESET}${BOLD} Cloning your workspace...${RESET}"
echo ""

mkdir -p "$WORKSPACE_BASE"
WORKSPACE_DIR="$WORKSPACE_BASE/$REPO_NAME"

if [ -d "$WORKSPACE_DIR/.git" ]; then
  git -C "$WORKSPACE_DIR" pull --ff-only || true
  echo -e "  ${GREEN}✓ Pulled latest at $WORKSPACE_DIR${RESET}"
else
  git clone "$REPO_URL" "$WORKSPACE_DIR"
  echo -e "  ${GREEN}✓ Cloned to $WORKSPACE_DIR${RESET}"
fi

# Set commit identity per-repo
git -C "$WORKSPACE_DIR" config user.name "$NAME"
git -C "$WORKSPACE_DIR" config user.email "$EMAIL"

# ── Desktop alias (macOS only, best-effort) ────────────────────────
if [ "$PLATFORM" = "macos" ]; then
  osascript -e "tell application \"Finder\" to make alias file to (POSIX file \"$WORKSPACE_DIR\") at desktop" >/dev/null 2>&1 \
    && echo -e "  ${GREEN}✓ Created Desktop alias${RESET}" \
    || echo -e "  ${DIM}  Desktop alias skipped (Finder unavailable)${RESET}"
fi

echo ""

# ── [4/4] Install plugin ───────────────────────────────────────────
echo -e "${BRAND_ACCENT}  [4/4]${RESET}${BOLD} Installing the Claude Code plugin...${RESET}"
echo ""

# Idempotent re-runs: remove existing entries first
claude plugin marketplace remove incubator-os 2>/dev/null || true

claude plugin marketplace add austinmarchese/incubator-os-plugin
echo -e "  ${GREEN}✓ Added marketplace: austinmarchese/incubator-os-plugin${RESET}"

claude plugin install inc-os@incubator-os
echo -e "  ${GREEN}✓ Installed plugin: inc-os@incubator-os${RESET}"

# Install Anthropic's frontend-design plugin (UI/web tooling)
echo -e "  ${DIM}Installing frontend-design from Anthropic's plugin marketplace...${RESET}"
claude plugin marketplace add anthropics/claude-plugins-official 2>/dev/null || true
claude plugin install frontend-design@claude-plugins-official 2>/dev/null || true
echo -e "  ${GREEN}✓ Installed plugin: frontend-design@claude-plugins-official${RESET}"

# ── Ensure CLAUDE.md exists ────────────────────────────────────────
# Block content is injected by sweep.mjs on first SessionStart (one source of truth).
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
mkdir -p "$(dirname "$CLAUDE_MD")"
touch "$CLAUDE_MD"
echo -e "  ${GREEN}✓ Ensured ~/.claude/CLAUDE.md exists (block injected via sweep.mjs)${RESET}"

echo ""

# ── Done ───────────────────────────────────────────────────────────
echo ""
echo -e "${BRAND_ORANGE}  ╭──────────────────────────────────────────────────────╮${RESET}"
echo -e "${BRAND_ORANGE}  │                                                      │${RESET}"
echo -e "${BRAND_ORANGE}  │  ${BOLD}You're all set!${RESET}${BRAND_ORANGE}                                     │${RESET}"
echo -e "${BRAND_ORANGE}  │                                                      │${RESET}"
echo -e "${BRAND_ORANGE}  ╰──────────────────────────────────────────────────────╯${RESET}"
echo ""
echo -e "${BOLD}  Get started in Claude Desktop:${RESET}"
echo ""
echo -e "  ${BRAND_ACCENT}1.${RESET} Open the ${BOLD}Claude${RESET} desktop app"
echo -e "  ${BRAND_ACCENT}2.${RESET} Switch to the ${BOLD}Claude Code${RESET} toggle"
echo -e "  ${BRAND_ACCENT}3.${RESET} Select this folder when prompted:"
echo -e "       ${BOLD}$WORKSPACE_DIR${RESET}"
echo -e "  ${BRAND_ACCENT}4.${RESET} Try one of these commands:"
echo ""
echo -e "       ${BOLD}/inc-os:update${RESET}   — pull latest and brief on changes"
echo -e "       ${BOLD}/inc-os:save${RESET}     — review and push your work"
echo -e "       ${BOLD}/inc-os:improve${RESET}  — make your system smarter"
echo -e "       ${BOLD}/inc-os:ingest${RESET}   — process a source into the KB"
echo ""
echo -e "  ${DIM}Note: on first session, Claude Code may show a one-time${RESET}"
echo -e "  ${DIM}approval prompt for the Incubator OS plugin. Approve it.${RESET}"
echo ""
