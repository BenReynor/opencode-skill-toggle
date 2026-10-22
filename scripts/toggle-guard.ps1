#Requires -Version 5.1
<#
  toggle-guard.ps1 — Guard and auto-updater for skill-toggle on Windows.

  Two jobs, both using the newest versioned release (one tag per build, so the
  content of every URL never changes) and verifying the SHA256 against
  SHA256SUMS:

    1. Restore — if opencode.exe was replaced (by the official autoupdate, by
       "opencode upgrade" or by a manual install of the clean binary), it
       reinstalls the skill-toggle build.
    2. Update — if a newer skill-toggle build has been published, it installs
       it. The check is cached, so it costs one API call per hour.

  It is launched by a Scheduled Task created by install.ps1 (every 15 min and at
  logon). You can also run it manually:
    powershell -NoProfile -ExecutionPolicy Bypass -File toggle-guard.ps1

  And force a version check right now:
    powershell -NoProfile -ExecutionPolicy Bypass -File toggle-guard.ps1 -Update

  Optional variables:
    $env:GH_REPO                 repository (default BenReynor/opencode-skill-toggle)
    $env:TOGGLE_GUARD_LOG        log path (default %USERPROFILE%\.opencode\toggle-guard.log)
    $env:TOGGLE_GUARD_CACHE_MIN  minutes the version check is cached (default 60)
#>
param(
  [switch]$Update
)

$ErrorActionPreference = "Stop"

$Repo = if ($env:GH_REPO) { $env:GH_REPO } else { "BenReynor/opencode-skill-toggle" }
$Bin = Join-Path $HOME ".opencode\bin\opencode.exe"
$Marker = "$Bin.sha256"
$Log = if ($env:TOGGLE_GUARD_LOG) { $env:TOGGLE_GUARD_LOG } else { Join-Path $HOME ".opencode\toggle-guard.log" }
$Platform = "windows-x64"
$CacheDir = Join-Path $HOME ".opencode"
$CacheTag = Join-Path $CacheDir ".toggle-guard-tag"
$CacheSums = Join-Path $CacheDir ".toggle-guard-sums"
$CacheMin = if ($env:TOGGLE_GUARD_CACHE_MIN) { [int]$env:TOGGLE_GUARD_CACHE_MIN } else { 60 }

function Guard-Log([string]$Msg) {
  $Line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Msg
  Add-Content -LiteralPath $Log -Value $Line -ErrorAction SilentlyContinue
  Write-Output $Line
}

# --- Release info (cached) ----------------------------------------------------
# Each build is published to a unique tag (toggle-X.Y.Z or toggle-X.Y.Z-r<build>):
# its content never changes, so the download never mixes old binaries from the
# CDN (unlike "latest", which is overwritten on every build). The cache keeps
# the tag and the SHA256SUMS of that release, so a normal run only hashes the
# local binary and compares it: one API call per hour.
function Get-ReleaseInfo {
  $tag = $null
  $sums = $null
  try {
    $fresh = $false
    if ((Test-Path -LiteralPath $CacheTag) -and (Test-Path -LiteralPath $CacheSums)) {
      $age = (Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $CacheTag).LastWriteTimeUtc
      if ($age.TotalMinutes -lt $CacheMin) { $fresh = $true }
    }
    if ($Update -or -not $fresh) {
      $rels = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=30" `
        -Headers @{ "User-Agent" = "opencode-skill-toggle" } -ErrorAction Stop
      $t = $rels | Where-Object { $_.tag_name -like "toggle-*" } | Select-Object -First 1 -ExpandProperty tag_name
      if ($t) { $tag = $t } else { $tag = "latest" }
      $sumsText = (Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/$tag/SHA256SUMS" `
        -UseBasicParsing -ErrorAction Stop).Content
      New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
      Set-Content -LiteralPath $CacheTag -Value $tag -NoNewline
      Set-Content -LiteralPath $CacheSums -Value $sumsText -NoNewline
    }
    if (-not (Test-Path -LiteralPath $CacheTag)) { return $null }
    $tag = (Get-Content -LiteralPath $CacheTag -Raw).Trim()
    if (-not (Test-Path -LiteralPath $CacheSums)) { return $null }
    $sums = Get-Content -LiteralPath $CacheSums
  } catch { }
  if (-not $tag -or -not $sums) { return $null }
  return [pscustomobject]@{
    Tag  = $tag
    Base = "https://github.com/$Repo/releases/download/$tag"
    Sums = $sums
  }
}

if (-not (Test-Path -LiteralPath $Bin)) { exit 0 }

$Release = Get-ReleaseInfo
if (-not $Release) { Guard-Log "could not resolve the newest release; skipping"; exit 0 }

$Cur = (Get-FileHash -LiteralPath $Bin -Algorithm SHA256).Hash.ToLower()
$Want = if (Test-Path -LiteralPath $Marker) { (Get-Content -LiteralPath $Marker -Raw).Trim().ToLower() } else { "" }

# No marker → this binary was not installed by us: never hijack it.
if (-not $Want) { exit 0 }

$Published = @{}
foreach ($line in $Release.Sums) {
  if ($line -match '^\s*([0-9a-fA-F]{64})\s+(\S+)') { $Published[$Matches[1].ToLower()] = $Matches[2] }
}

$Reason = ""
if ($Cur -ne $Want) {
  $Reason = "restore"     # the binary was replaced (official autoupdate)
} elseif (-not $Published.ContainsKey($Cur)) {
  $Reason = "update"      # our hash is not published anymore → older build
}

# The cached release can be older than the installed binary (for example right
# after the installer updated it). Refresh once before "updating" downwards.
if ($Reason -eq "update") {
  $Update = $true
  $Fresh = Get-ReleaseInfo
  if ($Fresh) {
    $Release = $Fresh
    $Published = @{}
    foreach ($line in $Release.Sums) {
      if ($line -match '^\s*([0-9a-fA-F]{64})\s+(\S+)') { $Published[$Matches[1].ToLower()] = $Matches[2] }
    }
    if ($Published.ContainsKey($Cur)) { $Reason = "" }
  }
}

if (-not $Reason) { exit 0 }

if ($Reason -eq "restore") {
  Guard-Log "binary differs from the marker (official autoupdate?): reinstalling skill-toggle"
} else {
  Guard-Log "a newer skill-toggle build is published ($($Release.Tag)): updating"
}

# Same directory/volume as the binary so Move-Item is atomic.
$Tmp = Join-Path (Split-Path -Parent $Bin) "opencode-toggle.$PID.download"
$Backup = "$Bin.bak"

try {
  Invoke-WebRequest -Uri "$($Release.Base)/opencode-$Platform" -OutFile $Tmp -UseBasicParsing

  $ExpectedLine = $Release.Sums | Where-Object { $_ -match "(?i)opencode-$Platform\s*$" } | Select-Object -First 1
  if (-not $ExpectedLine) {
    Guard-Log "ERROR: no checksum for opencode-$Platform in SHA256SUMS"
    exit 1
  }
  $Expected = ($ExpectedLine -split '\s+')[0].ToLower()
  $Actual = (Get-FileHash -LiteralPath $Tmp -Algorithm SHA256).Hash.ToLower()
  if ($Actual -ne $Expected) {
    Guard-Log "ERROR: SHA256 does not match; binary discarded"
    exit 1
  }

  # Keep the current binary until the new one is proven to work (rollback).
  Remove-Item -LiteralPath $Backup -Force -ErrorAction SilentlyContinue
  Copy-Item -LiteralPath $Bin -Destination $Backup -Force -ErrorAction SilentlyContinue

  # Replacement with retries in case opencode.exe is open during these seconds.
  $Ok = $false
  for ($i = 0; $i -lt 3; $i++) {
    try {
      Move-Item -LiteralPath $Tmp -Destination $Bin -Force -ErrorAction Stop
      $Ok = $true
      break
    } catch {
      Start-Sleep -Seconds 2
    }
  }
  if (-not $Ok) {
    Guard-Log "ERROR: could not replace $Bin (process in use?)"
    exit 1
  }

  # The new binary must run: otherwise the previous one is restored.
  $Ver = ""
  try { $Ver = (& $Bin --version 2>$null | Select-Object -First 1) } catch { $Ver = "" }
  if (-not $Ver) {
    Guard-Log "ERROR: the new binary does not run; restoring the previous one"
    if (Test-Path -LiteralPath $Backup) {
      Move-Item -LiteralPath $Backup -Destination $Bin -Force -ErrorAction SilentlyContinue
    }
    exit 1
  }

  Set-Content -LiteralPath $Marker -Value $Actual -NoNewline
  Guard-Log "skill-toggle installed OK ($Platform, $Ver, sha256 $Actual)"

  # Residue cleanup from previous versions (backups .bak / temporary files).
  $Cleanup = Join-Path $HOME ".opencode\toggle-cleanup.ps1"
  if (Test-Path -LiteralPath $Cleanup) {
    $PrevKeep = $env:TOGGLE_CLEANUP_KEEP_BACKUP
    $env:TOGGLE_CLEANUP_KEEP_BACKUP = "1"
    try { & $Cleanup | Out-Null } finally {
      if ($null -eq $PrevKeep) { Remove-Item Env:\TOGGLE_CLEANUP_KEEP_BACKUP -ErrorAction SilentlyContinue }
      else { $env:TOGGLE_CLEANUP_KEEP_BACKUP = $PrevKeep }
    }
  }
} finally {
  Remove-Item -LiteralPath $Tmp -Force -ErrorAction SilentlyContinue
}
