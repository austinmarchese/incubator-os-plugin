# Incubator OS Plugin Installer (Windows)
#
# Usage:
#   iwr https://incubator-os.com/install.ps1?t=<token> | iex

$ErrorActionPreference = "Stop"

$InstallToken = "__INSTALL_TOKEN_PLACEHOLDER__"
$ApiBase = if ($env:INCUBATOR_OS_API_BASE) { $env:INCUBATOR_OS_API_BASE } else { "https://www.incubator-os.com" }
$IncOsDir = Join-Path $HOME ".incubator-os"
$WorkspaceBase = Join-Path $HOME "incubator"

# Track best-effort failures for end-of-install summary
$Failures = @()
function Track-Failure { param([string]$msg) $script:Failures += $msg }

# Refresh $env:Path from registry so newly-installed CLIs (npm, node, claude)
# are visible in the current PS session without a shell restart.
function Refresh-Path {
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# ── Brand colors (matches install.sh on macOS/Linux) ───────────────
# 24-bit ANSI escapes; modern Windows conhost (Win10 1511+) supports
# VT processing. Enable it explicitly for PS 5.1 just in case.
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
Write-Host "  ${BRAND_ORANGE}│  Incubator OS — Your AI Workspace       │${RESET}"
Write-Host "  ${BRAND_ORANGE}╰─────────────────────────────────────────╯${RESET}"
Write-Host ""

if (-not $InstallToken -or $InstallToken -eq "__INSTALL_TOKEN_PLACEHOLDER__") {
  Write-Host "  ${RED}No install token provided. Use the URL Austin sent you.${RESET}"
  exit 1
}

# ── Require winget ─────────────────────────────────────────────────
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host ""
  Write-Host "  ${RED}winget is not installed.${RESET}"
  Write-Host ""
  Write-Host "  ${BOLD}Install 'App Installer' from the Microsoft Store, then rerun this script:${RESET}"
  Write-Host ""
  Write-Host "    ${BRAND_ACCENT}https://apps.microsoft.com/detail/9NBLGGH4NNS1${RESET}"
  Write-Host ""
  Write-Host "  ${DIM}Docs: https://aka.ms/getwinget${RESET}"
  Write-Host ""
  exit 1
}

# ── [1/4] Dependencies ─────────────────────────────────────────────
Write-Host "${BRAND_ACCENT}  [1/4]${RESET}${BOLD} Installing dependencies...${RESET}"
Write-Host ""

# Pick up any PATH changes from previous installs (winget updates the
# registry but the current PS process keeps a stale copy of $env:Path).
Refresh-Path

function Ensure-Cmd {
  param([string]$Cmd, [string]$WingetId, [string]$Label)
  if (-not (Get-Command $Cmd -ErrorAction SilentlyContinue)) {
    winget install --id $WingetId --accept-source-agreements --accept-package-agreements --silent | Out-Null
    Refresh-Path
    Write-Host "  ${GREEN}✓ $Label (installed)${RESET}"
  } else {
    Write-Host "  ${GREEN}✓ $Label (already installed)${RESET}"
  }
}

Ensure-Cmd git "Git.Git" "git"
Ensure-Cmd node "OpenJS.NodeJS.LTS" "node"

# ── Ingest dependencies (best-effort; non-fatal) ───────────────────
# yt-dlp: used by scripts/fetch_youtube_transcript.py for title/channel metadata
if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
  try {
    winget install --id yt-dlp.yt-dlp --accept-source-agreements --accept-package-agreements --silent | Out-Null
    Write-Host "  ${GREEN}✓ yt-dlp (installed)${RESET}"
  } catch {
    Write-Host "  ${YELLOW}! yt-dlp not available — YouTube transcript metadata will fall back to video ID only${RESET}"
    Track-Failure "yt-dlp (optional, YouTube ingest)"
  }
} else {
  Write-Host "  ${GREEN}✓ yt-dlp (already installed)${RESET}"
}

# youtube-transcript-api: Python package used by scripts/fetch_youtube_transcript.py
# Skip Microsoft Store alias stubs (WindowsApps path) — those are install shortcuts, not Python.
$PyCmd = $null
foreach ($name in @("python3", "python")) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -notlike "*\WindowsApps\*") {
    $PyCmd = $name
    break
  }
}

if ($PyCmd) {
  $hasApi = & {
    $ErrorActionPreference = "Continue"
    & $args[0] -c "import youtube_transcript_api" 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
  } $PyCmd
  if ($hasApi) {
    Write-Host "  ${GREEN}✓ youtube-transcript-api (already installed)${RESET}"
  } else {
    $pipOk = & {
      $ErrorActionPreference = "Continue"
      & $args[0] -m pip install --quiet youtube-transcript-api 2>&1 | Out-Null
      return ($LASTEXITCODE -eq 0)
    } $PyCmd
    if ($pipOk) {
      Write-Host "  ${GREEN}✓ youtube-transcript-api (installed)${RESET}"
    } else {
      Write-Host "  ${YELLOW}! youtube-transcript-api not installed — run: pip install youtube-transcript-api${RESET}"
      Track-Failure "youtube-transcript-api (optional, YouTube ingest)"
    }
  }
} else {
  Write-Host "  ${YELLOW}! python not found — YouTube ingest requires manual setup (see scripts/fetch_youtube_transcript.py)${RESET}"
  Track-Failure "python (optional, YouTube ingest)"
}

Refresh-Path
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "  ${RED}npm is not on PATH yet. Open a new PowerShell window and rerun the install command.${RESET}"
    Track-Failure "Claude Code (npm not on PATH - rerun in a new shell)"
  } else {
    npm install -g @anthropic-ai/claude-code | Out-Null
    Refresh-Path
    Write-Host "  ${GREEN}✓ Claude Code (installed)${RESET}"
  }
} else {
  Write-Host "  ${GREEN}✓ Claude Code (already installed)${RESET}"
}

# Claude Desktop (best-effort, non-fatal)
$ClaudeDesktopPath = Join-Path $env:LOCALAPPDATA "AnthropicClaude\claude.exe"
if (Test-Path $ClaudeDesktopPath) {
  Write-Host "  ${GREEN}✓ Claude Desktop (already installed)${RESET}"
} else {
  try {
    winget install --id Anthropic.Claude --accept-source-agreements --accept-package-agreements --silent | Out-Null
    Write-Host "  ${GREEN}✓ Claude Desktop (installed)${RESET}"
  } catch {
    Write-Host "  ${YELLOW}! Claude Desktop install skipped — install manually from https://claude.ai/download${RESET}"
    Track-Failure "Claude Desktop (manual install needed: https://claude.ai/download)"
  }
}

Write-Host ""

# ── [2/4] Workspace credentials ────────────────────────────────────
Write-Host "${BRAND_ACCENT}  [2/4]${RESET}${BOLD} Setting up your workspace credentials...${RESET}"
Write-Host ""

# Partial-state recovery: skip credential fetch only if cached token hash
# matches current install token. Different install URL (e.g. a new client
# repo) must NOT reuse the previous client's cached creds.
$AuthFile = Join-Path $IncOsDir "auth.json"
$TokenFile = Join-Path $IncOsDir "token"
$SkipFetch = $false

$sha = [System.Security.Cryptography.SHA256]::Create()
$InstallTokenHash = -join (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($InstallToken))) | ForEach-Object { $_.ToString("x2") })
$sha.Dispose()

if ((Test-Path $AuthFile) -and (Test-Path $TokenFile)) {
  try {
    $ExistingAuth = Get-Content $AuthFile -Raw | ConvertFrom-Json
    if ($ExistingAuth.client_id -and $ExistingAuth.install_token_hash -eq $InstallTokenHash) {
      $Resp = [PSCustomObject]@{
        name = $ExistingAuth.name
        email = $ExistingAuth.email
        client_id = $ExistingAuth.client_id
        auth_token = $ExistingAuth.token
        repo_url = $ExistingAuth.repo_url
        pat = Get-Content $TokenFile -Raw
      }
      $SkipFetch = $true
      Write-Host "  ${GREEN}✓ Fetched credentials for $($Resp.name) (cached)${RESET}"
    }
  } catch {}
}

if (-not $SkipFetch) {
  $Resp = Invoke-RestMethod -Uri "$ApiBase/api/incubator-os/install/$InstallToken" -Method Get
  if ($Resp.error) {
    Write-Host "  ${RED}Install failed: $($Resp.error)${RESET}"
    Write-Host "  ${DIM}Contact Austin for a fresh install URL.${RESET}"
    exit 1
  }
  Write-Host "  ${GREEN}✓ Fetched credentials for $($Resp.name)${RESET}"
}

$RepoName = ($Resp.repo_url -replace '\.git$','').Split('/')[-1]

# Write auth files
New-Item -ItemType Directory -Force -Path $IncOsDir | Out-Null

$AuthJson = @{
  token = $Resp.auth_token
  email = $Resp.email
  name = $Resp.name
  client_id = $Resp.client_id
  api_base = $ApiBase
  repo_url = $Resp.repo_url
  install_token_hash = $InstallTokenHash
} | ConvertTo-Json -Compress

[System.IO.File]::WriteAllText($AuthFile, $AuthJson, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($TokenFile, $Resp.pat, [System.Text.UTF8Encoding]::new($false))

# Restrict ACLs to current user only (Windows equivalent of chmod 600)
icacls $AuthFile /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
icacls $TokenFile /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
Write-Host "  ${GREEN}✓ Wrote ~/.incubator-os/auth.json (ACL: current user only)${RESET}"
Write-Host "  ${GREEN}✓ Wrote ~/.incubator-os/token (ACL: current user only)${RESET}"

# URL-scoped credential helper.
# Git on Windows runs credential helpers via the bundled msys/MinGW
# sh.exe. A .cmd helper doesn't execute cleanly under that shell, so
# git falls back to Git Credential Manager and pops a "Connect to
# GitHub" dialog. A POSIX sh script runs cleanly (Git for Windows
# ships with bash).
$HelperPath = Join-Path $IncOsDir "credential-helper.sh"
# Use $HOME (msys sh resolves it to %USERPROFILE%) to match install.sh exactly.
# Avoids baked-in Windows paths that msys may interpret inconsistently.
$helperBody = @"
#!/bin/sh
[ "`$1" = "get" ] || exit 0
echo "username=austinmarchese"
echo "password=`$(cat "`$HOME/.incubator-os/token")"
"@
$helperBodyLf = $helperBody -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($HelperPath, $helperBodyLf, [System.Text.UTF8Encoding]::new($false))

$HelperPathGit = $HelperPath -replace '\\', '/'

# Clear any prior entries for this URL scope, then add an empty-string
# reset (clears inherited helpers like gh's `!gh auth git-credential` or
# Git Credential Manager from running before ours), then add ours.
# PS drops empty string args to native exes, so we shell out to cmd.exe
# for the reset entry — cmd preserves "" correctly.
git config --global --unset-all "credential.https://github.com/austinmarchese.helper" 2>&1 | Out-Null
cmd /c 'git config --global --add "credential.https://github.com/austinmarchese.helper" ""' | Out-Null
git config --global --add "credential.https://github.com/austinmarchese.helper" $HelperPathGit
Write-Host "  ${GREEN}✓ Configured URL-scoped git credential helper for github.com/austinmarchese/*${RESET}"
Write-Host "  ${GREEN}✓ Set commit identity on workspace: $($Resp.name) <$($Resp.email)>${RESET}"

Write-Host ""

# ── [3/4] Clone workspace ──────────────────────────────────────────
Write-Host "${BRAND_ACCENT}  [3/4]${RESET}${BOLD} Cloning your workspace...${RESET}"
Write-Host ""

New-Item -ItemType Directory -Force -Path $WorkspaceBase | Out-Null
$WorkspaceDir = Join-Path $WorkspaceBase $RepoName
$InstallLog = Join-Path $IncOsDir "install.log"

if (Test-Path (Join-Path $WorkspaceDir ".git")) {
  $branch = & {
    $ErrorActionPreference = "Continue"
    (git -C $WorkspaceDir rev-parse --abbrev-ref HEAD 2>$null).Trim()
  }
  if ($branch -and $branch -ne "HEAD") {
    & {
      $ErrorActionPreference = "Continue"
      git -C $WorkspaceDir pull --ff-only 2>&1 | Out-Null
    }
    Write-Host "  ${GREEN}✓ Pulled latest at $WorkspaceDir${RESET}"
  } else {
    Write-Host "  ${YELLOW}! workspace on detached HEAD — leaving existing state intact${RESET}"
  }
} else {
  # Stream clone output so the user can see progress (and any auth
  # prompts or stalls). Disable git's interactive prompts via env var
  # so a bad credential helper can't block on stdin forever.
  $env:GIT_TERMINAL_PROMPT = "0"
  # Belt + suspenders: -c credential.helper="" wipes inherited helpers
  # (GCM, gh) for this command, then -c credential.helper=<ours> sets
  # ours. Beats GCM even if the global URL-scoped helper lost the race.
  # Also tee output to install.log so failure summary can reference real stderr.
  "=== git clone $($Resp.repo_url) at $(Get-Date -Format o) ===" | Out-File -FilePath $InstallLog -Encoding utf8
  & {
    $ErrorActionPreference = "Continue"
    git -c "credential.helper=" `
        -c "credential.helper=$HelperPathGit" `
        clone --progress $Resp.repo_url $WorkspaceDir 2>&1 |
      Tee-Object -FilePath $InstallLog -Append |
      ForEach-Object { Write-Host "    $_" }
  }
  Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
  if (Test-Path (Join-Path $WorkspaceDir ".git")) {
    Write-Host "  ${GREEN}✓ Cloned to $WorkspaceDir${RESET}"
  } else {
    Write-Host "  ${RED}✗ Clone failed. Full output: $InstallLog${RESET}"
    Track-Failure "git clone of $($Resp.repo_url) failed - see $InstallLog"
  }
}

# Bake credential helper into repo-local config so future ops (push/pull/fetch
# from inside the workspace) use our PAT regardless of global git state. Local
# config beats global, so this survives `gh auth setup-git`, GCM reinstalls,
# and any later changes to ~/.gitconfig.
if (Test-Path (Join-Path $WorkspaceDir ".git")) {
  & {
    $ErrorActionPreference = "Continue"
    git -C $WorkspaceDir config --local --replace-all credential.helper "" 2>&1 | Out-Null
    git -C $WorkspaceDir config --local --add credential.helper $HelperPathGit 2>&1 | Out-Null
  }
  git -C $WorkspaceDir config user.name $Resp.name
  git -C $WorkspaceDir config user.email $Resp.email
}

# Start Menu shortcut
$StartMenuShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Incubator OS.lnk"
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($StartMenuShortcut)
$Shortcut.TargetPath = $WorkspaceDir
$Shortcut.Save()
Write-Host "  ${GREEN}✓ Created Start Menu shortcut${RESET}"

Write-Host ""

# ── [4/4] Install plugin ───────────────────────────────────────────
Write-Host "${BRAND_ACCENT}  [4/4]${RESET}${BOLD} Installing the Claude Code plugin...${RESET}"
Write-Host ""

Refresh-Path
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "  ${RED}! claude CLI not on PATH — open a new PowerShell window and rerun this install command.${RESET}"
  Track-Failure "Plugin install skipped - claude CLI not on PATH yet (rerun in a new shell)"
} else {
  & {
    $ErrorActionPreference = "Continue"
    claude plugin marketplace remove incubator-os 2>&1 | Out-Null
    claude plugin marketplace add austinmarchese/incubator-os-plugin 2>&1 | Out-Null
    claude plugin install "inc-os@incubator-os" 2>&1 | Out-Null
  }
  Write-Host "  ${GREEN}✓ Added marketplace: austinmarchese/incubator-os-plugin${RESET}"
  Write-Host "  ${GREEN}✓ Installed plugin: inc-os@incubator-os${RESET}"

  Write-Host "  ${DIM}Installing frontend-design from Anthropic's plugin marketplace...${RESET}"
  & {
    $ErrorActionPreference = "Continue"
    claude plugin marketplace add anthropics/claude-plugins-official 2>&1 | Out-Null
    claude plugin install "frontend-design@claude-plugins-official" 2>&1 | Out-Null
  }
  Write-Host "  ${GREEN}✓ Installed plugin: frontend-design@claude-plugins-official${RESET}"
}

# Ensure CLAUDE.md exists; block injected by sweep.mjs on first SessionStart.
$ClaudeMd = Join-Path $HOME ".claude\CLAUDE.md"
New-Item -ItemType Directory -Force -Path (Split-Path $ClaudeMd) | Out-Null
if (-not (Test-Path $ClaudeMd)) { New-Item -ItemType File -Path $ClaudeMd | Out-Null }
Write-Host "  ${GREEN}✓ Ensured ~/.claude/CLAUDE.md exists (block injected via sweep.mjs)${RESET}"

Write-Host ""

# ── Done ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ${BRAND_ORANGE}╭──────────────────────────────────────────────────────╮${RESET}"
Write-Host "  ${BRAND_ORANGE}│                                                      │${RESET}"
Write-Host "  ${BRAND_ORANGE}│  ${BOLD}You're all set!${RESET}${BRAND_ORANGE}                                     │${RESET}"
Write-Host "  ${BRAND_ORANGE}│                                                      │${RESET}"
Write-Host "  ${BRAND_ORANGE}╰──────────────────────────────────────────────────────╯${RESET}"
Write-Host ""
Write-Host "  ${BOLD}Next step: open the Claude Desktop app${RESET}"
Write-Host "  ${DIM}(the graphical app, not your terminal — we installed it for you)${RESET}"
Write-Host "  ${DIM}If it's missing, download it: https://claude.ai/download${RESET}"
Write-Host ""
Write-Host "  ${BRAND_ACCENT}1.${RESET} Open the ${BOLD}Claude${RESET} desktop app (search 'Claude' in Start menu)"
Write-Host "  ${BRAND_ACCENT}2.${RESET} Switch to the ${BOLD}Claude Code${RESET} toggle"
Write-Host "  ${BRAND_ACCENT}3.${RESET} Select this folder when prompted:"
Write-Host "       ${BOLD}$WorkspaceDir${RESET}"
Write-Host "  ${BRAND_ACCENT}4.${RESET} Try one of these commands:"
Write-Host ""
Write-Host "       ${BOLD}/inc-os:update-system${RESET}    — pull latest and brief on changes"
Write-Host "       ${BOLD}/inc-os:save-system${RESET}      — review and push your work"
Write-Host "       ${BOLD}/inc-os:improve-system${RESET}   — improve your system from recent sessions"
Write-Host "       ${BOLD}/inc-os:add-new-resource${RESET} — add a new resource to your knowledge base"
Write-Host ""
Write-Host "  ${DIM}Note: on first session, Claude Code may show a one-time${RESET}"
Write-Host "  ${DIM}approval prompt for the Incubator OS plugin. Approve it.${RESET}"
Write-Host ""
Write-Host "  ${DIM}You can safely rerun this install script anytime — it's idempotent.${RESET}"
Write-Host ""

# ── Install summary (only if optional components failed) ───────────
if ($Failures.Count -gt 0) {
  Write-Host "  ${YELLOW}⚠ Some optional components didn't install cleanly:${RESET}"
  Write-Host ""
  foreach ($f in $Failures) {
    Write-Host "    ${YELLOW}•${RESET} $f"
  }
  Write-Host ""
  Write-Host "  ${BOLD}Share this with Austin if you need help:${RESET}"
  Write-Host ""
  Write-Host "  ${DIM}─────────────────────────────────────────${RESET}"
  Write-Host "  Install report for $($Resp.name) <$($Resp.email)>"
  Write-Host "  Platform: Windows ($([System.Environment]::OSVersion.VersionString))"
  Write-Host "  Client ID: $($Resp.client_id)"
  Write-Host "  Failures:"
  foreach ($f in $Failures) {
    Write-Host "    - $f"
  }
  Write-Host "  ${DIM}─────────────────────────────────────────${RESET}"
  Write-Host ""

  # If we captured a clone log, walk the user through sharing it.
  if (Test-Path $InstallLog) {
    Write-Host "  ${BOLD}If git clone failed, send Austin the install log:${RESET}"
    Write-Host ""
    Write-Host "    ${BRAND_ACCENT}1.${RESET} Open the log:"
    Write-Host "       ${DIM}notepad `"$InstallLog`"${RESET}"
    Write-Host ""
    Write-Host "    ${BRAND_ACCENT}2.${RESET} Or copy it to your clipboard:"
    Write-Host "       ${DIM}Get-Content `"$InstallLog`" | Set-Clipboard${RESET}"
    Write-Host ""
    Write-Host "    ${BRAND_ACCENT}3.${RESET} Paste the contents to Austin (Slack/email)."
    Write-Host ""
  }
}
