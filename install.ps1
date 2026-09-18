#Requires -Version 5.1
<#
  Installs opencode + skill-toggle (custom build of the opencode binary) on Windows.

  Usage:
    powershell -ExecutionPolicy Bypass -c "irm https://github.com/BenReynor/opencode-skill-toggle/releases/download/latest/install.ps1 | iex"

  Optional:
    $env:GH_REPO = "youruser/opencode-skill-toggle"  before running.

  Downloads the current-platform binary from the newest versioned release,
  backs up the previous installation and replaces %USERPROFILE%\.opencode\bin\opencode.exe.
#>
[CmdletBinding()]
param(
  [string]$Repo = $env:GH_REPO
)

if (-not $Repo) {
  $Repo = "BenReynor/opencode-skill-toggle"
}

$ErrorActionPreference = "Stop"

function Write-Step($Msg) {
  Write-Host ">> $Msg"
}

# --- Detect platform --------------------------------------------------------
$arch = $env:PROCESSOR_ARCHITECTURE
if (-not $arch) {
  $arch = $env:PROCESSOR_ARCHITEW6432
}
switch ($arch) {
  "AMD64" { $Platform = "windows-x64" }
  "ARM64" {
    Write-Warning "Windows ARM64: no native arm64 binary is published; using windows-x64 (emulation on Windows 11 ARM)."
    $Platform = "windows-x64"
  }
  default { throw "Unsupported platform: $arch" }
}
Write-Step "Platform: $Platform"

# --- Obtain the binary --------------------------------------------------------
$BinDir = Join-Path $HOME ".opencode\bin"
$Final = Join-Path $BinDir "opencode.exe"

# Every build is published to a unique tag (toggle-X.Y.Z or toggle-X.Y.Z-r<build>):
# its content never changes, so the download never mixes old binaries from the
# CDN cache (unlike "latest", which is overwritten on every build).
function Resolve-ReleaseBase {
  $tag = "latest"
  try {
    $rels = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=30" `
      -Headers @{ "User-Agent" = "opencode-skill-toggle" } -ErrorAction Stop
    $t = $rels | Where-Object { $_.tag_name -like "toggle-*" } | Select-Object -First 1 -ExpandProperty tag_name
    if ($t) { $tag = $t }
  } catch { }
  return "https://github.com/$Repo/releases/download/$tag"
}
$ReleaseBase = Resolve-ReleaseBase
Write-Step "Release: $($ReleaseBase -replace '^.*/download/','')"

$Url = "$ReleaseBase/opencode-$Platform"

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

Write-Step "Downloading: $Url"
$Tmp = Join-Path $BinDir "opencode.download"
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
  & curl.exe -fsSL $Url -o $Tmp
  if ($LASTEXITCODE -ne 0) { throw "curl could not download $Url (exit $LASTEXITCODE)" }
} else {
  Invoke-WebRequest -Uri $Url -OutFile $Tmp -UseBasicParsing
}

# --- SHA256 verification ------------------------------------------------------
$ShaUrl = "$ReleaseBase/SHA256SUMS"
$ShaTmp = Join-Path $BinDir "opencode-sha256.download"
Write-Step "Verifying SHA256 against $ShaUrl"
try {
  if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    & curl.exe -fsSL $ShaUrl -o $ShaTmp
    if ($LASTEXITCODE -ne 0) { throw "curl could not download $ShaUrl (exit $LASTEXITCODE)" }
  } else {
    Invoke-WebRequest -Uri $ShaUrl -OutFile $ShaTmp -UseBasicParsing
  }
  # The SHA256SUMS format is "<hash>  opencode-<platform>"
  $ExpectedLine = Get-Content $ShaTmp | Where-Object { $_ -match "(?i)opencode-$Platform\s*$" } | Select-Object -First 1
  if (-not $ExpectedLine) {
    Write-Warning "No checksum for opencode-$Platform; continuing without verification."
  } else {
    $Expected = ($ExpectedLine -split '\s+')[0]
    $Actual = (Get-FileHash -Path $Tmp -Algorithm SHA256).Hash.ToLower()
    if ($Actual -ne $Expected.ToLower()) {
      Remove-Item -Force $Tmp, $ShaTmp -ErrorAction SilentlyContinue
      throw "SHA256 verification failed for opencode-$Platform. Expected: $Expected. Got: $Actual. The binary was discarded because of possible tampering."
    }
    Write-Step "SHA256 verified correctly"
  }
} finally {
  if (Test-Path $ShaTmp) { Remove-Item -Force $ShaTmp }
}

# --- Backup of the current binary ---------------------------------------------
if (Test-Path $Final) {
  $Backup = "$Final.bak"
  if (-not (Test-Path $Backup)) {
    Copy-Item $Final $Backup -Force
    Write-Step "Backup saved: $Backup"
  } else {
    Write-Step "Backup exists: $Backup (not overwritten)"
  }
}

# --- Install ------------------------------------------------------------------
# Windows locks an executable that is running, so retry for a few seconds if
# opencode is in use (the running process keeps its old copy; new sessions use
# the new binary). This mirrors the retry logic in toggle-guard.ps1.
$Installed = $false
for ($i = 0; $i -lt 5; $i++) {
  try {
    Move-Item -LiteralPath $Tmp -Destination $Final -Force -ErrorAction Stop
    $Installed = $true
    break
  } catch {
    Start-Sleep -Seconds 2
  }
}
if (-not $Installed) {
  throw "Could not replace $Final (is opencode running?). The downloaded binary was kept at $Tmp."
}
Write-Step "Installed: $Final"

# --- Marker for the guard ---
$ActualHash = (Get-FileHash -LiteralPath $Final -Algorithm SHA256).Hash.ToLower()
Set-Content -LiteralPath "$Final.sha256" -Value $ActualHash -NoNewline

# --- Residue cleanup -------------------------------------------------------------
# Removes backups and temporary files from previous versions on update.
$Cleanup = Join-Path $HOME ".opencode\toggle-cleanup.ps1"
if ($PSScriptRoot) {
  $LocalCleanup = Join-Path $PSScriptRoot "scripts\toggle-cleanup.ps1"
  if (Test-Path -LiteralPath $LocalCleanup) {
    Copy-Item -LiteralPath $LocalCleanup -Destination $Cleanup -Force
  }
}
if (-not (Test-Path -LiteralPath $Cleanup)) {
  Write-Step "Downloading toggle-cleanup.ps1"
  Invoke-WebRequest -Uri "$ReleaseBase/toggle-cleanup.ps1" -OutFile $Cleanup -UseBasicParsing -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath $Cleanup) {
  try {
    & $Cleanup
    Write-Step "Residues of previous versions removed"
  } catch {
    Write-Warning "The residue cleanup did not finish properly; retry with: powershell -File `"$Cleanup`""
  }
}

# --- Anti-overwrite guard (Task Scheduler) -------------------------------------
if ($env:TOGGLE_GUARD -ne "0") {
  $Guard = Join-Path $HOME ".opencode\toggle-guard.ps1"
  if ($PSScriptRoot) {
    $LocalGuard = Join-Path $PSScriptRoot "scripts\toggle-guard.ps1"
    if (Test-Path -LiteralPath $LocalGuard) {
      Copy-Item -LiteralPath $LocalGuard -Destination $Guard -Force
    } else {
      Write-Step "Downloading toggle-guard.ps1"
      Invoke-WebRequest -Uri "$ReleaseBase/toggle-guard.ps1" -OutFile $Guard -UseBasicParsing
    }
  } else {
    Write-Step "Downloading toggle-guard.ps1"
    Invoke-WebRequest -Uri "$ReleaseBase/toggle-guard.ps1" -OutFile $Guard -UseBasicParsing
  }

  $TaskName = "opencode-skill-toggle-guard"
  $Action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Guard`""
  $TriggerRun = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration ([TimeSpan]::MaxValue)
  $TriggerLogon = New-ScheduledTaskTrigger -AtLogOn

  try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action `
      -Trigger $TriggerRun, $TriggerLogon -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Write-Step "Anti-overwrite guard enabled (Task Scheduler: $TaskName)"
    Write-Step "  - log: $(Join-Path $HOME '.opencode\toggle-guard.log')"
    Write-Step "  - disable: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
  } catch {
    Write-Warning "Could not register the guard: $($_.Exception.Message)"
  }
} else {
  Write-Step "Anti-overwrite guard not installed (TOGGLE_GUARD=0)"
}

Write-Host ""
Write-Host @"
Important notice:
  - This is a custom (non-official) build. It keeps your real opencode.db.
  - When downloading from GitHub Releases, the binary is verified against SHA256SUMS.
  - The anti-overwrite guard is enabled by default: it restores the toggle if the
    official update replaces it. (Alternative: "autoupdate": false in
    opencode.json disables the official autoupdate; see README / Updates.)
  - As an unsigned binary, Windows SmartScreen may warn you the first time:
      click "More info" > "Run anyway".
  - Automatic residue cleanup on update (removes .bak and temporary files from
      previous versions; keeps one with TOGGLE_CLEANUP_KEEP_BACKUP=1).
  - Restart opencode for the new binary to take effect.
"@
