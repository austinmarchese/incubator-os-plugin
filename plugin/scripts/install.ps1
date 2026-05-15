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

Write-Host ""
Write-Host "  Incubator OS Plugin Installer" -ForegroundColor White
Write-Host ""

if (-not $InstallToken -or $InstallToken -eq "__INSTALL_TOKEN_PLACEHOLDER__") {
  Write-Host "  No install token provided. Use the URL Austin sent you." -ForegroundColor Red
  exit 1
}

# ── Require winget ─────────────────────────────────────────────────
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host ""
  Write-Host "  winget is not installed." -ForegroundColor Red
  Write-Host ""
  Write-Host "  Install 'App Installer' from the Microsoft Store, then rerun this script:" -ForegroundColor White
  Write-Host ""
  Write-Host "    https://apps.microsoft.com/detail/9NBLGGH4NNS1" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "  Docs: https://aka.ms/getwinget" -ForegroundColor DarkGray
  Write-Host ""
  exit 1
}

# ── Install winget-managed deps if missing ─────────────────────────
# Pick up any PATH changes from previous installs (winget updates the
# registry but the current PS process keeps a stale copy of $env:Path).
Refresh-Path

function Ensure-Cmd {
  param([string]$Cmd, [string]$WingetId)
  if (-not (Get-Command $Cmd -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing $Cmd..."
    winget install --id $WingetId --accept-source-agreements --accept-package-agreements --silent
    Refresh-Path
  }
}

Ensure-Cmd git "Git.Git"
Ensure-Cmd node "OpenJS.NodeJS.LTS"

# ── Ingest dependencies (best-effort; non-fatal) ───────────────────
# yt-dlp: used by scripts/fetch_youtube_transcript.py for title/channel metadata
if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
  try {
    winget install --id yt-dlp.yt-dlp --accept-source-agreements --accept-package-agreements --silent
    Write-Host "  + yt-dlp (installed)" -ForegroundColor Green
  } catch {
    Write-Host "  ! yt-dlp not available - YouTube transcript metadata will fall back to video ID only" -ForegroundColor Yellow
    Track-Failure "yt-dlp (optional, YouTube ingest)"
  }
} else {
  Write-Host "  + yt-dlp (already installed)" -ForegroundColor Green
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
  # Run python in a child scope so native-command stderr doesn't halt the script under $ErrorActionPreference=Stop.
  $hasApi = & {
    $ErrorActionPreference = "Continue"
    & $args[0] -c "import youtube_transcript_api" 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
  } $PyCmd
  if ($hasApi) {
    Write-Host "  + youtube-transcript-api (already installed)" -ForegroundColor Green
  } else {
    $pipOk = & {
      $ErrorActionPreference = "Continue"
      & $args[0] -m pip install --quiet youtube-transcript-api 2>&1 | Out-Null
      return ($LASTEXITCODE -eq 0)
    } $PyCmd
    if ($pipOk) {
      Write-Host "  + youtube-transcript-api (installed)" -ForegroundColor Green
    } else {
      Write-Host "  ! youtube-transcript-api not installed - run: pip install youtube-transcript-api" -ForegroundColor Yellow
      Track-Failure "youtube-transcript-api (optional, YouTube ingest)"
    }
  }
} else {
  Write-Host "  ! python not found - YouTube ingest requires manual setup (see scripts/fetch_youtube_transcript.py)" -ForegroundColor Yellow
  Track-Failure "python (optional, YouTube ingest)"
}

Refresh-Path
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "  Installing Claude Code..."
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "  npm is not on PATH yet. Open a new PowerShell window and rerun the install command." -ForegroundColor Red
    Track-Failure "Claude Code (npm not on PATH - rerun in a new shell)"
  } else {
    npm install -g @anthropic-ai/claude-code
    Refresh-Path
  }
}

# ── Install Claude Desktop (best-effort, non-fatal) ────────────────
$ClaudeDesktopPath = Join-Path $env:LOCALAPPDATA "AnthropicClaude\claude.exe"
if (Test-Path $ClaudeDesktopPath) {
  Write-Host "  + Claude Desktop (already installed)" -ForegroundColor Green
} else {
  try {
    winget install --id Anthropic.Claude --accept-source-agreements --accept-package-agreements --silent | Out-Null
    Write-Host "  + Claude Desktop (installed)" -ForegroundColor Green
  } catch {
    Write-Host "  ! Claude Desktop install skipped - install manually from https://claude.ai/download" -ForegroundColor Yellow
    Track-Failure "Claude Desktop (manual install needed: https://claude.ai/download)"
  }
}

# ── Partial-state recovery: skip credential fetch if auth.json valid ──
$AuthFile = Join-Path $IncOsDir "auth.json"
$TokenFile = Join-Path $IncOsDir "token"
$SkipFetch = $false

if ((Test-Path $AuthFile) -and (Test-Path $TokenFile)) {
  try {
    $ExistingAuth = Get-Content $AuthFile -Raw | ConvertFrom-Json
    if ($ExistingAuth.client_id) {
      Write-Host "  Found existing install state, skipping credential fetch."
      $Resp = [PSCustomObject]@{
        name = $ExistingAuth.name
        email = $ExistingAuth.email
        client_id = $ExistingAuth.client_id
        auth_token = $ExistingAuth.token
        repo_url = $ExistingAuth.repo_url
        pat = Get-Content $TokenFile -Raw
      }
      $SkipFetch = $true
    }
  } catch {}
}

if (-not $SkipFetch) {
  Write-Host "  Fetching your workspace credentials..."
  $Resp = Invoke-RestMethod -Uri "$ApiBase/api/incubator-os/install/$InstallToken" -Method Get
  if ($Resp.error) {
    Write-Host "  Install failed: $($Resp.error)" -ForegroundColor Red
    exit 1
  }
}

$RepoName = ($Resp.repo_url -replace '\.git$','').Split('/')[-1]

# ── Write auth files ───────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $IncOsDir | Out-Null

$AuthJson = @{
  token = $Resp.auth_token
  email = $Resp.email
  name = $Resp.name
  client_id = $Resp.client_id
  api_base = $ApiBase
  repo_url = $Resp.repo_url
} | ConvertTo-Json -Compress

[System.IO.File]::WriteAllText($AuthFile, $AuthJson, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($TokenFile, $Resp.pat, [System.Text.UTF8Encoding]::new($false))

# Restrict ACLs to current user only (Windows equivalent of chmod 600)
icacls $AuthFile /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
icacls $TokenFile /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null

# ── URL-scoped credential helper ───────────────────────────────────
$HelperPath = Join-Path $IncOsDir "credential-helper.cmd"
@"
@echo off
if /I "%~1" NEQ "get" exit /b 0
echo username=austinmarchese
set /p TOKEN=<"%USERPROFILE%\.incubator-os\token"
echo password=%TOKEN%
"@ | Set-Content -Path $HelperPath -Encoding ASCII

# Git on Windows runs credential helpers via msys sh, which mangles
# backslashes. Use forward slashes when storing the path in git config
# so sh resolves it as a real file instead of a stripped string.
# Then --replace-all so reruns don't accumulate duplicate entries.
# (We skip the `helper = ""` chain-reset trick: PowerShell drops empty
# string args when invoking native exes, which would leave the config
# in a broken state. Instead, we rely on git's behavior of stopping at
# the first helper that returns valid credentials — when ours works,
# GCM is never queried and the popup never appears.)
$HelperPathGit = $HelperPath -replace '\\', '/'
git config --global --replace-all "credential.https://github.com/austinmarchese.helper" $HelperPathGit

# ── Clone repo ─────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $WorkspaceBase | Out-Null
$WorkspaceDir = Join-Path $WorkspaceBase $RepoName

if (Test-Path (Join-Path $WorkspaceDir ".git")) {
  Write-Host "  Workspace already cloned, attempting to pull latest..."
  $branch = & {
    $ErrorActionPreference = "Continue"
    (git -C $WorkspaceDir rev-parse --abbrev-ref HEAD 2>$null).Trim()
  }
  if ($branch -and $branch -ne "HEAD") {
    & {
      $ErrorActionPreference = "Continue"
      git -C $WorkspaceDir pull --ff-only 2>&1 | Out-Null
    }
    Write-Host "  + pulled latest on $branch" -ForegroundColor Green
  } else {
    Write-Host "  ! workspace on detached HEAD - skipping pull, leaving existing state intact" -ForegroundColor Yellow
  }
} else {
  Write-Host "  Cloning workspace to $WorkspaceDir..."
  & {
    $ErrorActionPreference = "Continue"
    git clone $Resp.repo_url $WorkspaceDir 2>&1 | ForEach-Object { Write-Host "    $_" }
  }
}

git -C $WorkspaceDir config user.name $Resp.name
git -C $WorkspaceDir config user.email $Resp.email

# ── Start Menu shortcut ────────────────────────────────────────────
$StartMenuShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Incubator OS.lnk"
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($StartMenuShortcut)
$Shortcut.TargetPath = $WorkspaceDir
$Shortcut.Save()

# ── Install plugin ─────────────────────────────────────────────────
Write-Host "  Installing the Incubator OS plugin..."

Refresh-Path
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "  ! claude CLI not on PATH - open a new PowerShell window and rerun this install command." -ForegroundColor Red
  Track-Failure "Plugin install skipped - claude CLI not on PATH yet (rerun in a new shell)"
} else {
  # Run in child scope with Continue so claude's stderr (e.g. "Marketplace not found"
  # on first install) doesn't terminate under $ErrorActionPreference=Stop.
  & {
    $ErrorActionPreference = "Continue"
    claude plugin marketplace remove incubator-os 2>&1 | Out-Null
    claude plugin marketplace add austinmarchese/incubator-os-plugin
    claude plugin install "inc-os@incubator-os"
  }
}

# Install Anthropic's frontend-design plugin (UI/web tooling)
Write-Host "  Installing frontend-design from Anthropic's plugin marketplace..."
if (Get-Command claude -ErrorAction SilentlyContinue) {
  & {
    $ErrorActionPreference = "Continue"
    claude plugin marketplace add anthropics/claude-plugins-official 2>&1 | Out-Null
    claude plugin install "frontend-design@claude-plugins-official" 2>&1 | Out-Null
  }
  Write-Host "  + Installed plugin: frontend-design@claude-plugins-official" -ForegroundColor Green
} else {
  Write-Host "  ! Skipped frontend-design (claude CLI not on PATH yet)" -ForegroundColor Yellow
  Track-Failure "frontend-design plugin (claude CLI not on PATH - rerun in a new shell)"
}

# ── Ensure CLAUDE.md exists ────────────────────────────────────────
# Block content is injected by sweep.mjs on first SessionStart (one source of truth).
# Matches install.sh behavior; avoids PS Get-Content -Raw array quirks.
$ClaudeMd = Join-Path $HOME ".claude\CLAUDE.md"
New-Item -ItemType Directory -Force -Path (Split-Path $ClaudeMd) | Out-Null
if (-not (Test-Path $ClaudeMd)) { New-Item -ItemType File -Path $ClaudeMd | Out-Null }
Write-Host "  + Ensured ~/.claude/CLAUDE.md exists (block injected via sweep.mjs)" -ForegroundColor Green

Write-Host ""
Write-Host "  +---------------------------------------------------------+" -ForegroundColor DarkRed
Write-Host "  |                                                         |" -ForegroundColor DarkRed
Write-Host "  |  You're all set!                                        |" -ForegroundColor DarkRed
Write-Host "  |                                                         |" -ForegroundColor DarkRed
Write-Host "  +---------------------------------------------------------+" -ForegroundColor DarkRed
Write-Host ""
Write-Host "  Next step: open the Claude Desktop app" -ForegroundColor White
Write-Host "  (the graphical app, not your terminal - we installed it for you)" -ForegroundColor DarkGray
Write-Host "  If it's missing, download it: https://claude.ai/download" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  1." -NoNewline -ForegroundColor Yellow
Write-Host " Open the " -NoNewline
Write-Host "Claude" -NoNewline -ForegroundColor White
Write-Host " desktop app (search 'Claude' in Start menu)"
Write-Host "  2." -NoNewline -ForegroundColor Yellow
Write-Host " Switch to the " -NoNewline
Write-Host "Claude Code" -NoNewline -ForegroundColor White
Write-Host " toggle"
Write-Host "  3." -NoNewline -ForegroundColor Yellow
Write-Host " Select this folder when prompted:"
Write-Host "       $WorkspaceDir" -ForegroundColor White
Write-Host "  4." -NoNewline -ForegroundColor Yellow
Write-Host " Try one of these commands:"
Write-Host ""
Write-Host "       /inc-os:update" -NoNewline -ForegroundColor White
Write-Host "   -- pull latest and brief on changes"
Write-Host "       /inc-os:save" -NoNewline -ForegroundColor White
Write-Host "     -- review and push your work"
Write-Host "       /inc-os:improve" -NoNewline -ForegroundColor White
Write-Host "  -- make your system smarter"
Write-Host "       /inc-os:ingest" -NoNewline -ForegroundColor White
Write-Host "   -- process a source into the KB"
Write-Host ""
Write-Host "  Note: on first session, Claude Code may show a one-time" -ForegroundColor DarkGray
Write-Host "  approval prompt for the Incubator OS plugin. Approve it." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  You can safely rerun this install script anytime - it's idempotent." -ForegroundColor DarkGray
Write-Host ""

# ── Install summary (only if optional components failed) ───────────
if ($Failures.Count -gt 0) {
  Write-Host "  ! Some optional components didn't install cleanly:" -ForegroundColor Yellow
  Write-Host ""
  foreach ($f in $Failures) {
    Write-Host "    - $f" -ForegroundColor Yellow
  }
  Write-Host ""
  Write-Host "  Share this with Austin if you need help:" -ForegroundColor White
  Write-Host ""
  Write-Host "  -----------------------------------------" -ForegroundColor DarkGray
  Write-Host "  Install report for $($Resp.name) <$($Resp.email)>"
  Write-Host "  Platform: Windows ($([System.Environment]::OSVersion.VersionString))"
  Write-Host "  Client ID: $($Resp.client_id)"
  Write-Host "  Failures:"
  foreach ($f in $Failures) {
    Write-Host "    - $f"
  }
  Write-Host "  -----------------------------------------" -ForegroundColor DarkGray
  Write-Host ""
}
