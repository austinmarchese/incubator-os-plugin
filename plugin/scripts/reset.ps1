# Incubator OS Reset (Windows)
#
# Wipes local Incubator OS state so a fresh `install.ps1` can run cleanly
# on a machine that already had git/GitHub configured for something else.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -Command "irm 'https://www.incubator-os.com/reset.ps1' | iex"
#
# Flags (set via env var before piping):
#   $env:INC_OS_RESET_DEEP = "1"   # also clears Windows Credential Manager entries for github.com
#   $env:INC_OS_RESET_YES  = "1"   # skip confirmation prompt

$ErrorActionPreference = "Stop"

$IncOsDir = Join-Path $HOME ".incubator-os"
$WorkspaceBase = Join-Path $HOME "incubator"
$Deep = $env:INC_OS_RESET_DEEP -eq "1"
$Yes = $env:INC_OS_RESET_YES -eq "1"

# ── VT color setup (mirrors install.ps1) ───────────────────────────
try {
  $vtSig = @'
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
  if (-not ('Win32.ConsoleMode' -as [type])) {
    Add-Type -Name ConsoleMode -Namespace Win32 -MemberDefinition $vtSig | Out-Null
  }
  $stdOut = [Win32.ConsoleMode]::GetStdHandle(-11)
  $mode = 0
  if ([Win32.ConsoleMode]::GetConsoleMode($stdOut, [ref]$mode)) {
    [Win32.ConsoleMode]::SetConsoleMode($stdOut, $mode -bor 0x0004) | Out-Null
  }
} catch {}

$ESC = [char]27
$BRAND_ORANGE = "$ESC[38;2;166;68;34m"
$BRAND_ACCENT = "$ESC[38;2;204;119;90m"
$GREEN  = "$ESC[32m"
$YELLOW = "$ESC[33m"
$RED    = "$ESC[31m"
$BOLD   = "$ESC[1m"
$DIM    = "$ESC[2m"
$RESET  = "$ESC[0m"

Write-Host ""
Write-Host "  ${BRAND_ORANGE}╭─────────────────────────────────────────╮${RESET}"
Write-Host "  ${BRAND_ORANGE}│  Incubator OS — Reset                   │${RESET}"
Write-Host "  ${BRAND_ORANGE}╰─────────────────────────────────────────╯${RESET}"
Write-Host ""

Write-Host "  ${BOLD}This will remove:${RESET}"
Write-Host "    - ${DIM}$IncOsDir${RESET}"
Write-Host "    - ${DIM}$WorkspaceBase\<your-workspace>${RESET} (only the one tied to this install)"
Write-Host "    - ${DIM}credential.https://github.com/austinmarchese.*${RESET} entries in ~/.gitconfig"
if ($Deep) {
  Write-Host "    ${YELLOW}[--deep]${RESET} ${DIM}all github.com entries in Windows Credential Manager${RESET}"
}
Write-Host ""
Write-Host "  ${BOLD}It will NOT touch:${RESET} your other repos, user.name/user.email, SSH keys, or any non-github.com creds."
Write-Host ""

if (-not $Yes) {
  $reply = Read-Host "  Continue? [y/N]"
  if ($reply -notmatch '^[Yy]') {
    Write-Host "  ${YELLOW}Aborted.${RESET}"
    exit 0
  }
  Write-Host ""
}

# ── [1/4] Identify workspace from auth.json (best-effort) ──────────
Write-Host "${BRAND_ACCENT}  [1/4]${RESET}${BOLD} Identifying workspace...${RESET}"
$WorkspaceDir = $null
$AuthFile = Join-Path $IncOsDir "auth.json"
if (Test-Path $AuthFile) {
  try {
    $Auth = Get-Content $AuthFile -Raw | ConvertFrom-Json
    if ($Auth.repo_url) {
      $RepoName = ($Auth.repo_url -replace '\.git$','').Split('/')[-1]
      $WorkspaceDir = Join-Path $WorkspaceBase $RepoName
      Write-Host "  ${GREEN}✓ Found workspace: $WorkspaceDir${RESET}"
    }
  } catch {
    Write-Host "  ${YELLOW}! Could not parse auth.json — workspace dir will be skipped${RESET}"
  }
} else {
  Write-Host "  ${DIM}No auth.json found — workspace dir will be skipped${RESET}"
}
Write-Host ""

# ── [2/4] Remove Incubator OS state ────────────────────────────────
Write-Host "${BRAND_ACCENT}  [2/4]${RESET}${BOLD} Removing Incubator OS state...${RESET}"
if (Test-Path $IncOsDir) {
  Remove-Item -Recurse -Force $IncOsDir
  Write-Host "  ${GREEN}✓ Removed $IncOsDir${RESET}"
} else {
  Write-Host "  ${DIM}~ $IncOsDir not present${RESET}"
}

if ($WorkspaceDir -and (Test-Path $WorkspaceDir)) {
  # If workspace has uncommitted changes, warn but proceed only with confirmation
  $hasChanges = $false
  if (Test-Path (Join-Path $WorkspaceDir ".git")) {
    & {
      $ErrorActionPreference = "Continue"
      $status = git -C $WorkspaceDir status --porcelain 2>$null
      if ($status) { $script:hasChanges = $true }
    }
  }
  if ($hasChanges -and -not $Yes) {
    Write-Host "  ${YELLOW}! Workspace has uncommitted changes:${RESET} $WorkspaceDir"
    $reply = Read-Host "    Delete anyway? [y/N]"
    if ($reply -notmatch '^[Yy]') {
      Write-Host "  ${YELLOW}~ Kept workspace dir intact${RESET}"
    } else {
      Remove-Item -Recurse -Force $WorkspaceDir
      Write-Host "  ${GREEN}✓ Removed $WorkspaceDir${RESET}"
    }
  } else {
    Remove-Item -Recurse -Force $WorkspaceDir
    Write-Host "  ${GREEN}✓ Removed $WorkspaceDir${RESET}"
  }
} elseif ($WorkspaceDir) {
  Write-Host "  ${DIM}~ $WorkspaceDir not present${RESET}"
}
Write-Host ""

# ── [3/4] Strip our URL-scoped credential helper from gitconfig ────
Write-Host "${BRAND_ACCENT}  [3/4]${RESET}${BOLD} Cleaning ~/.gitconfig...${RESET}"
if (Get-Command git -ErrorAction SilentlyContinue) {
  & {
    $ErrorActionPreference = "Continue"
    # --unset-all clears all values, --remove-section drops the [credential "<url>"] header too
    git config --global --unset-all "credential.https://github.com/austinmarchese.helper" 2>&1 | Out-Null
    git config --global --remove-section "credential.https://github.com/austinmarchese" 2>&1 | Out-Null
  }
  Write-Host "  ${GREEN}✓ Removed credential.https://github.com/austinmarchese.* entries${RESET}"
} else {
  Write-Host "  ${YELLOW}! git not found — skipping gitconfig cleanup${RESET}"
}
Write-Host ""

# ── [4/4] Optional: deep clean Windows Credential Manager ──────────
Write-Host "${BRAND_ACCENT}  [4/4]${RESET}${BOLD} Windows Credential Manager...${RESET}"
if ($Deep) {
  $targets = & {
    $ErrorActionPreference = "Continue"
    cmdkey /list 2>&1 | Select-String -Pattern "github.com" | ForEach-Object {
      if ($_.Line -match "Target:\s*(.+)$") { $Matches[1].Trim() }
    }
  }
  if ($targets) {
    foreach ($t in $targets) {
      & cmdkey /delete:$t 2>&1 | Out-Null
      Write-Host "  ${GREEN}✓ Deleted: $t${RESET}"
    }
  } else {
    Write-Host "  ${DIM}~ No github.com entries in Credential Manager${RESET}"
  }
} else {
  Write-Host "  ${DIM}~ Skipped (set INC_OS_RESET_DEEP=1 to clear github.com Credential Manager entries)${RESET}"
}
Write-Host ""

# ── Done ───────────────────────────────────────────────────────────
Write-Host "  ${GREEN}${BOLD}✓ Reset complete.${RESET}"
Write-Host ""
Write-Host "  ${BOLD}Next:${RESET} rerun your install URL in a fresh PowerShell window:"
Write-Host ""
Write-Host "    ${BRAND_ACCENT}powershell -ExecutionPolicy Bypass -Command ""irm 'https://www.incubator-os.com/install.ps1?t=<your-token>' | iex""${RESET}"
Write-Host ""
