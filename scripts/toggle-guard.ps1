#Requires -Version 5.1
<#
  toggle-guard.ps1 — Guard for skill-toggle on Windows.

  If opencode.exe was replaced (by the official autoupdate or by a manual
  install of the clean binary), it reinstalls the skill-toggle build,
  downloading it from the newest versioned release and verifying the SHA256.

  It is launched by a Scheduled Task created by install.ps1 (every 15 min and at
  logon). You can also run it manually:
    powershell -NoProfile -ExecutionPolicy Bypass -File toggle-guard.ps1

  Optional variables:
    $env:GH_REPO           repository (default BenReynor/opencode-skill-toggle)
    $env:TOGGLE_GUARD_LOG  log path (default %USERPROFILE%\.opencode\toggle-guard.log)
#>
$ErrorActionPreference = "Stop"

$Repo = if ($env:GH_REPO) { $env:GH_REPO } else { "BenReynor/opencode-skill-toggle" }
$Bin = Join-Path $HOME ".opencode\bin\opencode.exe"
$Marker = "$Bin.sha256"
$Log = if ($env:TOGGLE_GUARD_LOG) { $env:TOGGLE_GUARD_LOG } else { Join-Path $HOME ".opencode\toggle-guard.log" }
$Platform = "windows-x64"
$TagCache = Join-Path $HOME ".opencode\.toggle-guard-tag"

# Every build is published to a unique tag (toggle-X.Y.Z or toggle-X.Y.Z-r<build>):
# its content never changes, so the download never mixes old binaries from the
# CDN (unlike "latest", which is overwritten). Resolution uses a 6-hour cache so
# the API rate limit is not exhausted.
function Resolve-ReleaseBase {
  $tag = "latest"
  try {
    if (Test-Path -LiteralPath $TagCache) {
      $age = (Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $TagCache).LastWriteTimeUtc
      if ($age.TotalMinutes -lt 360) {
        $cached = (Get-Content -LiteralPath $TagCache -Raw).Trim()
        if ($cached) { return "https://github.com/$Repo/releases/download/$($cached)" }
      }
    }
    $rels = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=30" `
      -Headers @{ "User-Agent" = "opencode-skill-toggle" } -ErrorAction Stop
    $t = $rels | Where-Object { $_.tag_name -like "toggle-*" } | Select-Object -First 1 -ExpandProperty tag_name
    if ($t) {
      $tag = $t
      Set-Content -LiteralPath $TagCache -Value $tag -NoNewline -ErrorAction SilentlyContinue
    }
  } catch { }
  return "https://github.com/$Repo/releases/download/$tag"
}

$ReleaseBase = Resolve-ReleaseBase

function Guard-Log([string]$Msg) {
  $Line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Msg
  Add-Content -LiteralPath $Log -Value $Line -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $Bin)) { exit 0 }

$Cur = (Get-FileHash -LiteralPath $Bin -Algorithm SHA256).Hash.ToLower()
$Want = if (Test-Path -LiteralPath $Marker) { (Get-Content -LiteralPath $Marker -Raw).Trim().ToLower() } else { "" }

if (-not $Want -or $Cur -eq $Want) { exit 0 }

Guard-Log "binary differs from the marker: the official autoupdate may have replaced it; reinstalling skill-toggle"

$Tmp = Join-Path $env:TEMP "opencode-toggle.download"
$ShaTmp = Join-Path $env:TEMP "opencode-toggle.sha"

try {
  Invoke-WebRequest -Uri "$ReleaseBase/opencode-$Platform" -OutFile $Tmp -UseBasicParsing
  Invoke-WebRequest -Uri "$ReleaseBase/SHA256SUMS" -OutFile $ShaTmp -UseBasicParsing

  $ExpectedLine = Get-Content -LiteralPath $ShaTmp | Where-Object { $_ -match "(?i)opencode-$Platform\s*$" } | Select-Object -First 1
  if (-not $ExpectedLine) {
    Guard-Log "ERROR: no checksum for opencode-$Platform"
    exit 1
  }

  $Expected = ($ExpectedLine -split '\s+')[0].ToLower()
  $Actual = (Get-FileHash -LiteralPath $Tmp -Algorithm SHA256).Hash.ToLower()
  if ($Actual -ne $Expected) {
    Guard-Log "ERROR: SHA256 does not match; binary discarded"
    Remove-Item -LiteralPath $Tmp, $ShaTmp -Force -ErrorAction SilentlyContinue
    exit 1
  }

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

  Set-Content -LiteralPath $Marker -Value $Actual -NoNewline
  Guard-Log "skill-toggle reinstalled OK ($Platform, sha256 $Actual)"

  # Residue cleanup from previous versions (backups .bak / temporary files).
  $Cleanup = Join-Path $HOME ".opencode\toggle-cleanup.ps1"
  if (Test-Path -LiteralPath $Cleanup) {
    & $Cleanup | Out-Null
  }
} finally {
  Remove-Item -LiteralPath $ShaTmp -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Tmp -Force -ErrorAction SilentlyContinue
}