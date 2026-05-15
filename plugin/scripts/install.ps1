# Incubator OS Plugin Installer (Windows)
#
# Usage:
#   iwr https://incubator-os.com/install.ps1?t=<token> | iex

$ErrorActionPreference = "Stop"

$InstallToken = "__INSTALL_TOKEN_PLACEHOLDER__"
$ApiBase = if ($env:INCUBATOR_OS_API_BASE) { $env:INCUBATOR_OS_API_BASE } else { "https://www.incubator-os.com" }
$IncOsDir = Join-Path $HOME ".incubator-os"
$WorkspaceBase = Join-Path $HOME "incubator"

Write-Host ""
Write-Host "  Incubator OS Plugin Installer" -ForegroundColor White
Write-Host ""

if (-not $InstallToken -or $InstallToken -eq "__INSTALL_TOKEN_PLACEHOLDER__") {
  Write-Host "  No install token provided. Use the URL Austin sent you." -ForegroundColor Red
  exit 1
}

# ── Install winget-managed deps if missing ─────────────────────────
function Ensure-Cmd {
  param([string]$Cmd, [string]$WingetId)
  if (-not (Get-Command $Cmd -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing $Cmd..."
    winget install --id $WingetId --accept-source-agreements --accept-package-agreements --silent
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
  }
} else {
  Write-Host "  + yt-dlp (already installed)" -ForegroundColor Green
}

# youtube-transcript-api: Python package used by scripts/fetch_youtube_transcript.py
$PyCmd = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } `
         elseif (Get-Command python -ErrorAction SilentlyContinue) { "python" } `
         else { $null }
if ($PyCmd) {
  $HasApi = & $PyCmd -c "import youtube_transcript_api" 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "  + youtube-transcript-api (already installed)" -ForegroundColor Green
  } else {
    try {
      & $PyCmd -m pip install --quiet youtube-transcript-api 2>$null
      Write-Host "  + youtube-transcript-api (installed)" -ForegroundColor Green
    } catch {
      Write-Host "  ! youtube-transcript-api not installed - run: pip install youtube-transcript-api" -ForegroundColor Yellow
    }
  }
} else {
  Write-Host "  ! python not found - YouTube ingest requires manual setup (see scripts/fetch_youtube_transcript.py)" -ForegroundColor Yellow
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "  Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
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

git config --global "credential.https://github.com/austinmarchese.helper" "`"$HelperPath`""

# ── Clone repo ─────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $WorkspaceBase | Out-Null
$WorkspaceDir = Join-Path $WorkspaceBase $RepoName

if (Test-Path (Join-Path $WorkspaceDir ".git")) {
  Write-Host "  Workspace already cloned, pulling latest..."
  git -C $WorkspaceDir pull --ff-only
} else {
  Write-Host "  Cloning workspace to $WorkspaceDir..."
  git clone $Resp.repo_url $WorkspaceDir
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

claude plugin marketplace remove incubator-os 2>$null
claude plugin marketplace add austinmarchese/incubator-os-plugin
claude plugin install "inc-os@incubator-os"

# Install Anthropic's frontend-design plugin (UI/web tooling)
Write-Host "  Installing frontend-design from Anthropic's plugin marketplace..."
claude plugin marketplace add anthropics/claude-plugins-official 2>$null
claude plugin install "frontend-design@claude-plugins-official" 2>$null
Write-Host "  + Installed plugin: frontend-design@claude-plugins-official" -ForegroundColor Green

# ── Inject CLAUDE.md block ─────────────────────────────────────────
$ClaudeMd = Join-Path $HOME ".claude\CLAUDE.md"
New-Item -ItemType Directory -Force -Path (Split-Path $ClaudeMd) | Out-Null
if (-not (Test-Path $ClaudeMd)) { New-Item -ItemType File -Path $ClaudeMd | Out-Null }

$BlockFile = Get-ChildItem -Path (Join-Path $HOME ".claude\plugins") -Filter "claude-md-block.txt" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like "*incubator-os*" } | Select-Object -First 1

if ($BlockFile) {
  $BlockContent = Get-Content $BlockFile.FullName -Raw
  $Existing = Get-Content $ClaudeMd -Raw
  $Cleaned = $Existing -replace '(?s)<!-- incubator-os-start -->.*?<!-- incubator-os-end -->', ''
  $NewContent = $Cleaned.TrimEnd() + "`n`n" + $BlockContent + "`n"
  $TempFile = "$ClaudeMd.tmp"
  Set-Content -Path $TempFile -Value $NewContent -Encoding UTF8
  Move-Item -Force $TempFile $ClaudeMd
}

Write-Host ""
Write-Host "  +---------------------------------------------------------+" -ForegroundColor DarkRed
Write-Host "  |                                                         |" -ForegroundColor DarkRed
Write-Host "  |  You're all set!                                        |" -ForegroundColor DarkRed
Write-Host "  |                                                         |" -ForegroundColor DarkRed
Write-Host "  +---------------------------------------------------------+" -ForegroundColor DarkRed
Write-Host ""
Write-Host "  Get started in Claude Desktop:" -ForegroundColor White
Write-Host ""
Write-Host "  1." -NoNewline -ForegroundColor Yellow
Write-Host " Open the " -NoNewline
Write-Host "Claude" -NoNewline -ForegroundColor White
Write-Host " desktop app"
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
