#Requires -Version 5.1
<#
  toggle-cleanup.ps1 — Residue cleanup for skill-toggle on Windows.

  Every time the binary is updated or restored, removes leftovers from previous
  versions in %USERPROFILE%\.opencode\bin (.bak backups and *.download / *.tmp
  temporary files), so they never accumulate hundreds of MB.

  What it keeps:
    - opencode.exe          (the active binary with skill-toggle)
    - opencode.exe.sha256   (the guard's marker)

  Optional variables:
    $env:TOGGLE_CLEANUP_KEEP_BACKUP=1  keep a single .bak
    $env:TOGGLE_CLEANUP_DRY_RUN=1      list without deleting (dry run)
    $env:TOGGLE_CLEANUP_LOG            log file (default %USERPROFILE%\.opencode\toggle-cleanup.log)

  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File toggle-cleanup.ps1
#>
$ErrorActionPreference = "Stop"

$Bin = Join-Path $HOME ".opencode\bin\opencode.exe"
$KeepBackup = $env:TOGGLE_CLEANUP_KEEP_BACKUP -eq "1"
$DryRun = $env:TOGGLE_CLEANUP_DRY_RUN -eq "1"
$Log = if ($env:TOGGLE_CLEANUP_LOG) { $env:TOGGLE_CLEANUP_LOG } else { Join-Path $HOME ".opencode\toggle-cleanup.log" }

function Cleanup-Log([string]$Msg) {
  $Line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Msg
  Add-Content -LiteralPath $Log -Value $Line -ErrorAction SilentlyContinue
}

$Dir = Split-Path -Parent $Bin
if (-not (Test-Path -LiteralPath $Dir)) { exit 0 }
$Name = Split-Path -Leaf $Bin

$targets = @()
Get-ChildItem -LiteralPath $Dir -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $leaf = $_.Name
  $isBak = $leaf -eq "$Name.bak" -or $leaf -like "$Name.*.bak"
  $isTmp = $leaf -like "$Name.download" -or $leaf -like "$Name.tmp*" -or $leaf -like ".opencode-*.download"
  if (-not ($isBak -or $isTmp)) { return }
  if ($KeepBackup -and $leaf -eq "$Name.bak") { return }
  if ($_.FullName -eq $Bin) { return }
  $targets += $_.FullName
}

if ($targets.Count -eq 0) { exit 0 }

if ($DryRun) {
  Write-Host ">> (dry run) pending deletion:"
  foreach ($t in $targets) { Write-Host "   - $t" }
  exit 0
}

foreach ($t in $targets) {
  Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue
  Cleanup-Log "removed residue: $t"
}