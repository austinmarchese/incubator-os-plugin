#!/bin/bash
# Incubator OS Reset (macOS / Linux)
#
# Wipes local Incubator OS state so a fresh `install.sh` can run cleanly
# on a machine that already had git/GitHub configured for something else.
#
# Usage:
#   curl -fsSL https://www.incubator-os.com/reset.sh | bash
#
# Env flags:
#   INC_OS_RESET_DEEP=1   # also clears macOS Keychain github.com entries
#   INC_OS_RESET_YES=1    # skip confirmation prompt

set -e

INC_OS_DIR="$HOME/.incubator-os"
WORKSPACE_BASE="$HOME/incubator"
DEEP="${INC_OS_RESET_DEEP:-0}"
YES="${INC_OS_RESET_YES:-0}"

BRAND_ORANGE='\033[38;2;166;68;34m'
BRAND_ACCENT='\033[38;2;204;119;90m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo ""
echo -e "${BRAND_ORANGE}  ╭─────────────────────────────────────────╮${RESET}"
echo -e "${BRAND_ORANGE}  │  Incubator OS — Reset                    │${RESET}"
echo -e "${BRAND_ORANGE}  ╰─────────────────────────────────────────╯${RESET}"
echo ""

echo -e "  ${BOLD}This will remove:${RESET}"
echo -e "    - ${DIM}$INC_OS_DIR${RESET}"
echo -e "    - ${DIM}$WORKSPACE_BASE/<your-workspace>${RESET} (only the one tied to this install)"
echo -e "    - ${DIM}credential.https://github.com/austinmarchese.*${RESET} entries in ~/.gitconfig"
if [ "$DEEP" = "1" ]; then
  echo -e "    ${YELLOW}[--deep]${RESET} ${DIM}all github.com entries in macOS Keychain${RESET}"
fi
echo ""
echo -e "  ${BOLD}It will NOT touch:${RESET} your other repos, user.name/user.email, SSH keys, or any non-github.com creds."
echo ""

if [ "$YES" != "1" ]; then
  read -r -p "  Continue? [y/N] " reply </dev/tty
  case "$reply" in
    [Yy]*) ;;
    *) echo -e "  ${YELLOW}Aborted.${RESET}"; exit 0 ;;
  esac
  echo ""
fi

OS="$(uname -s)"

# ── [1/4] Identify workspace from auth.json ────────────────────────
echo -e "${BRAND_ACCENT}  [1/4]${RESET}${BOLD} Identifying workspace...${RESET}"
WORKSPACE_DIR=""
if [ -f "$INC_OS_DIR/auth.json" ]; then
  REPO_URL="$(grep -o '"repo_url"[[:space:]]*:[[:space:]]*"[^"]*"' "$INC_OS_DIR/auth.json" | sed 's/.*"\(https[^"]*\)"/\1/' || true)"
  if [ -n "$REPO_URL" ]; then
    REPO_NAME="$(basename "${REPO_URL%.git}")"
    WORKSPACE_DIR="$WORKSPACE_BASE/$REPO_NAME"
    echo -e "  ${GREEN}✓ Found workspace: $WORKSPACE_DIR${RESET}"
  else
    echo -e "  ${YELLOW}! Could not parse repo_url from auth.json — workspace dir will be skipped${RESET}"
  fi
else
  echo -e "  ${DIM}No auth.json found — workspace dir will be skipped${RESET}"
fi
echo ""

# ── [2/4] Remove Incubator OS state ────────────────────────────────
echo -e "${BRAND_ACCENT}  [2/4]${RESET}${BOLD} Removing Incubator OS state...${RESET}"
if [ -d "$INC_OS_DIR" ]; then
  rm -rf "$INC_OS_DIR"
  echo -e "  ${GREEN}✓ Removed $INC_OS_DIR${RESET}"
else
  echo -e "  ${DIM}~ $INC_OS_DIR not present${RESET}"
fi

if [ -n "$WORKSPACE_DIR" ] && [ -d "$WORKSPACE_DIR" ]; then
  has_changes=0
  if [ -d "$WORKSPACE_DIR/.git" ]; then
    if [ -n "$(git -C "$WORKSPACE_DIR" status --porcelain 2>/dev/null)" ]; then
      has_changes=1
    fi
  fi
  if [ "$has_changes" = "1" ] && [ "$YES" != "1" ]; then
    echo -e "  ${YELLOW}! Workspace has uncommitted changes:${RESET} $WORKSPACE_DIR"
    read -r -p "    Delete anyway? [y/N] " reply </dev/tty
    case "$reply" in
      [Yy]*)
        rm -rf "$WORKSPACE_DIR"
        echo -e "  ${GREEN}✓ Removed $WORKSPACE_DIR${RESET}"
        ;;
      *)
        echo -e "  ${YELLOW}~ Kept workspace dir intact${RESET}"
        ;;
    esac
  else
    rm -rf "$WORKSPACE_DIR"
    echo -e "  ${GREEN}✓ Removed $WORKSPACE_DIR${RESET}"
  fi
elif [ -n "$WORKSPACE_DIR" ]; then
  echo -e "  ${DIM}~ $WORKSPACE_DIR not present${RESET}"
fi
echo ""

# ── [3/4] Strip our URL-scoped credential helper from gitconfig ────
echo -e "${BRAND_ACCENT}  [3/4]${RESET}${BOLD} Cleaning ~/.gitconfig...${RESET}"
if command -v git >/dev/null 2>&1; then
  git config --global --unset-all "credential.https://github.com/austinmarchese.helper" 2>/dev/null || true
  git config --global --remove-section "credential.https://github.com/austinmarchese" 2>/dev/null || true
  echo -e "  ${GREEN}✓ Removed credential.https://github.com/austinmarchese.* entries${RESET}"
else
  echo -e "  ${YELLOW}! git not found — skipping gitconfig cleanup${RESET}"
fi
echo ""

# ── [4/4] Optional: deep clean macOS Keychain ──────────────────────
echo -e "${BRAND_ACCENT}  [4/4]${RESET}${BOLD} Keychain cleanup...${RESET}"
if [ "$DEEP" = "1" ]; then
  if [ "$OS" = "Darwin" ]; then
    deleted=0
    # security delete-internet-password exits non-zero when no more matches; loop until that happens
    while security delete-internet-password -s github.com >/dev/null 2>&1; do
      deleted=$((deleted + 1))
    done
    if [ "$deleted" -gt 0 ]; then
      echo -e "  ${GREEN}✓ Deleted $deleted github.com Keychain entries${RESET}"
    else
      echo -e "  ${DIM}~ No github.com Keychain entries${RESET}"
    fi
  else
    # Linux: clear libsecret store if in use
    if command -v secret-tool >/dev/null 2>&1; then
      secret-tool clear server github.com 2>/dev/null || true
      echo -e "  ${GREEN}✓ Cleared github.com from libsecret${RESET}"
    else
      echo -e "  ${DIM}~ secret-tool not installed — skipping libsecret cleanup${RESET}"
    fi
  fi
else
  echo -e "  ${DIM}~ Skipped (set INC_OS_RESET_DEEP=1 to clear OS keychain github.com entries)${RESET}"
fi
echo ""

# ── Done ───────────────────────────────────────────────────────────
echo -e "  ${GREEN}${BOLD}✓ Reset complete.${RESET}"
echo ""
echo -e "  ${BOLD}Next:${RESET} rerun your install URL:"
echo ""
echo -e "    ${BRAND_ACCENT}curl -fsSL 'https://www.incubator-os.com/install.sh?t=<your-token>' | bash${RESET}"
echo ""
