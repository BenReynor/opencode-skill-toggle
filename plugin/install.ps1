#Requires -Version 5.1
<#
  Installs the skill-toggle plugin for opencode 2.x (Windows).

    irm https://raw.githubusercontent.com/BenReynor/opencode-skill-toggle/main/plugin/install.ps1 | iex

  Downloads skill-toggle-tui.js from the "latest" release, verifies it against
  SHA256SUMS.scripts and copies it to %USERPROFILE%\.config\opencode\plugins\skill-toggle\
  (or $env:XDG_CONFIG_HOME\opencode\...). The opencode binary and your sessions
  are not touched. Restart opencode afterwards.

  Uninstall: $env:SKILL_TOGGLE_UNINSTALL = "1" before running it.
#>
$ErrorActionPreference = "Stop"

$Repo = if ($env:GH_REPO) { $env:GH_REPO } else { "BenReynor/opencode-skill-toggle" }
$Base = "https://github.com/$Repo/releases/download/latest"
$ConfigRoot = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
$DestDir = Join-Path $ConfigRoot "opencode\plugins\skill-toggle"
$Dest = Join-Path $DestDir "tui.js"

if ($env:SKILL_TOGGLE_UNINSTALL -eq "1") {
  Remove-Item -LiteralPath $DestDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host ">> skill-toggle plugin removed ($DestDir). Restart opencode."
  return
}

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("skill-toggle-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
  Invoke-WebRequest -Uri "$Base/SHA256SUMS.scripts" -OutFile (Join-Path $Tmp "sums") -UseBasicParsing
  Invoke-WebRequest -Uri "$Base/skill-toggle-tui.js" -OutFile (Join-Path $Tmp "tui.js") -UseBasicParsing
  $Line = Get-Content (Join-Path $Tmp "sums") | Where-Object { $_ -match '^\s*[0-9a-fA-F]{64}\s+(\./)?skill-toggle-tui\.js\s*$' } | Select-Object -First 1
  if (-not $Line) { throw "No checksum for skill-toggle-tui.js in the release" }
  $Expected = ($Line.Trim() -split '\s+')[0].ToLower()
  $Actual = (Get-FileHash -LiteralPath (Join-Path $Tmp "tui.js") -Algorithm SHA256).Hash.ToLower()
  if ($Actual -ne $Expected) { throw "SHA256 mismatch; nothing installed" }
  Write-Host ">> Downloaded and verified skill-toggle-tui.js (SHA256 $Expected)"

  New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
  Move-Item -LiteralPath (Join-Path $Tmp "tui.js") -Destination $Dest -Force
  Write-Host ">> Installed: $Dest"
  Write-Host ">> Restart opencode, open a session and type /skill-toggle"
} finally {
  Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
