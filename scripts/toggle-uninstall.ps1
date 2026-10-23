<#
.SYNOPSIS
  Removes the skill-toggle install and restores official opencode.

.DESCRIPTION
  Stops and deletes the anti-overwrite guard (Scheduled Task), the helper
  scripts, the toggle state and the patched binary. Conversation data,
  settings and snapshots are kept.

.PARAMETER Yes
  Do not ask for confirmation (used by the TUI slash command).

.PARAMETER Purge
  Delete the opencode binary instead of restoring the official build.

.PARAMETER FromBackup
  Offline: restore from %USERPROFILE%\.opencode\bin\opencode.exe.bak.
#>
param(
  [switch]$Yes,
  [switch]$Purge,
  [switch]$FromBackup
)

$ErrorActionPreference = "Stop"

$OcDir = Join-Path $HOME ".opencode"
$BinDir = Join-Path $OcDir "bin"
$Bin = Join-Path $BinDir "opencode.exe"
$Data = Join-Path $HOME ".local\share\opencode"
$State = Join-Path $HOME ".local\state\opencode"
$Log = Join-Path $State "toggle-uninstall.log"
$TaskName = "opencode-skill-toggle-guard"

if ($Yes) {
  New-Item -ItemType Directory -Force -Path $State | Out-Null
  try { Start-Transcript -Path $Log -Append | Out-Null } catch { }
  Write-Host "=== $(Get-Date -Format o) uninstall (purge=$Purge) ==="
}

function Say([string]$Text) { Write-Host $Text }
function Warn([string]$Text) { Write-Warning $Text }

$Installed = (Test-Path $Bin) -or (Test-Path (Join-Path $OcDir "toggle-guard.ps1")) -or
  (Test-Path (Join-Path $OcDir ".toggle-guard-tag"))
if (-not $Installed) {
  Say "skill-toggle is not installed."
  if ($Yes) { try { Stop-Transcript | Out-Null } catch { } }
  exit 0
}

Say "This will remove the skill-toggle install:"
Say "  - anti-overwrite guard (Scheduled Task: $TaskName)"
Say "  - helper scripts in $OcDir"
Say "  - toggle state $Data\skills-toggle.json"
if ($Purge) {
  Say "  - opencode binary $Bin (deleted)"
} else {
  Say "  - opencode binary $Bin (replaced by the official build)"
}
Say "Your conversations, settings and snapshots are kept."
Say ""

if (-not $Yes) {
  $Reply = Read-Host "Continue? [y/N]"
  if ($Reply -notmatch '^(?i)y(es)?$') {
    Say "Cancelled."
    exit 1
  }
}

# --- Stop and remove the guard before touching the binary -------------------
try {
  Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  Say ">> guard stopped (Task Scheduler)"
} catch {
  Warn "could not remove the scheduled task: $($_.Exception.Message)"
}

function Install-Binary([string]$Source) {
  New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
  $Tmp = Join-Path $BinDir ("opencode.new." + $PID + ".exe")
  Copy-Item -LiteralPath $Source -Destination $Tmp -Force
  # The running opencode may still hold the .exe; wait for it to exit.
  for ($i = 0; $i -lt 30; $i++) {
    try {
      Move-Item -LiteralPath $Tmp -Destination $Bin -Force -ErrorAction Stop
      return $true
    } catch {
      Start-Sleep -Seconds 1
    }
  }
  Remove-Item -LiteralPath $Tmp -Force -ErrorAction SilentlyContinue
  return $false
}

function Get-OfficialAsset {
  $arch = $env:PROCESSOR_ARCHITECTURE
  switch ($arch) {
    "AMD64" { return "opencode-windows-x64.zip" }
    "ARM64" { return "opencode-windows-arm64.zip" }
    default { return $null }
  }
}

function Download-Official {
  $asset = Get-OfficialAsset
  if (-not $asset) {
    Warn "unsupported architecture: $env:PROCESSOR_ARCHITECTURE"
    return $false
  }
  $url = "https://github.com/anomalyco/opencode/releases/latest/download/$asset"
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("opencode-restore-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    Say ">> downloading official opencode ($asset)"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmp $asset) -UseBasicParsing
    Expand-Archive -LiteralPath (Join-Path $tmp $asset) -DestinationPath $tmp -Force
    $found = Get-ChildItem -Path $tmp -Filter "opencode.exe" -Recurse -File | Select-Object -First 1
    if (-not $found) {
      Warn "official archive did not contain opencode.exe"
      return $false
    }
    if (-not (Install-Binary $found.FullName)) {
      Warn "could not replace $Bin (is another opencode still running?)"
      return $false
    }
    return $true
  } catch {
    Warn "could not download the official build: $($_.Exception.Message)"
    return $false
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# --- Restore or delete the binary ------------------------------------------
$KeepBin = $false
if ($Purge) {
  Remove-Item -LiteralPath $Bin -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath "$Bin.bak" -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath "$Bin.sha256" -Force -ErrorAction SilentlyContinue
  Say ">> removed $Bin"
} elseif ($FromBackup -and (Test-Path "$Bin.bak")) {
  if (Install-Binary "$Bin.bak") {
    Remove-Item -LiteralPath "$Bin.bak" -Force -ErrorAction SilentlyContinue
    Say ">> restored $Bin from the local backup (unverified)"
  } else {
    $KeepBin = $true
    Warn "could not restore the backup; the current binary was left in place"
  }
} elseif (Download-Official) {
  Remove-Item -LiteralPath "$Bin.bak" -Force -ErrorAction SilentlyContinue
  Say ">> official opencode installed"
} else {
  $KeepBin = $true
  Warn "the official binary could not be restored; the current binary was left in place"
  Warn "install opencode with: irm https://opencode.ai/install | iex"
}

# --- Remove guard state, helper scripts and toggle state --------------------
Remove-Item -LiteralPath (Join-Path $OcDir ".toggle-guard-tag") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $OcDir ".toggle-guard-sums") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$Bin.sha256" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $OcDir "toggle-guard.ps1") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $OcDir "toggle-cleanup.ps1") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $OcDir "toggle-guard.log") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $OcDir "toggle-cleanup.log") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $Data "skills-toggle.json*") -Force -ErrorAction SilentlyContinue
Say ">> removed guard files and toggle state"

if (-not $KeepBin) {
  Remove-Item -LiteralPath (Join-Path $BinDir "opencode2.cmd") -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $BinDir "opencode2") -Force -ErrorAction SilentlyContinue
  if ($Purge) {
    Remove-Item -LiteralPath $BinDir -Force -ErrorAction SilentlyContinue
  }
}

Remove-Item -LiteralPath (Join-Path $OcDir "toggle-uninstall.ps1") -Force -ErrorAction SilentlyContinue
Say ">> done. Open a new terminal to use opencode again."

if ($Yes) { try { Stop-Transcript | Out-Null } catch { } }
