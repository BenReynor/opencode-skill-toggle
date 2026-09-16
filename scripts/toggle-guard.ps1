#Requires -Version 5.1
<#
  toggle-guard.ps1 — Guardián del skill-toggle para Windows.

  Si opencode.exe fue reemplazado (por el autoupdate oficial o por una
  instalación manual del binario limpio), reinstala la build con skill-toggle
  descargándola de GitHub Releases/latest y verificando el SHA256.

  Lo lanza un Scheduled Task creado por install.ps1 (cada 15 min y al iniciar
  sesión). Puedes ejecutarlo a mano:
    powershell -NoProfile -ExecutionPolicy Bypass -File toggle-guard.ps1

  Variables opcionales:
    $env:GH_REPO           repositorio (por defecto BenReynor/opencode-skill-toggle)
    $env:TOGGLE_GUARD_LOG  ruta del log (por defecto %USERPROFILE%\.opencode\toggle-guard.log)
#>
$ErrorActionPreference = "Stop"

$Repo = if ($env:GH_REPO) { $env:GH_REPO } else { "BenReynor/opencode-skill-toggle" }
$Bin = Join-Path $HOME ".opencode\bin\opencode.exe"
$Marker = "$Bin.sha256"
$Log = if ($env:TOGGLE_GUARD_LOG) { $env:TOGGLE_GUARD_LOG } else { Join-Path $HOME ".opencode\toggle-guard.log" }
$Platform = "windows-x64"

function Guard-Log([string]$Msg) {
  $Line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Msg
  Add-Content -LiteralPath $Log -Value $Line -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $Bin)) { exit 0 }

$Cur = (Get-FileHash -LiteralPath $Bin -Algorithm SHA256).Hash.ToLower()
$Want = if (Test-Path -LiteralPath $Marker) { (Get-Content -LiteralPath $Marker -Raw).Trim().ToLower() } else { "" }

if (-not $Want -or $Cur -eq $Want) { exit 0 }

Guard-Log "binario distinto al marcado: el autoupdate oficial pudo reemplazarlo; reinstalo skill-toggle"

$Tmp = Join-Path $env:TEMP "opencode-toggle.download"
$ShaTmp = Join-Path $env:TEMP "opencode-toggle.sha"

try {
  Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/latest/opencode-$Platform" -OutFile $Tmp -UseBasicParsing
  Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/latest/SHA256SUMS" -OutFile $ShaTmp -UseBasicParsing

  $ExpectedLine = Get-Content -LiteralPath $ShaTmp | Where-Object { $_ -match "(?i)opencode-$Platform\s*$" } | Select-Object -First 1
  if (-not $ExpectedLine) {
    Guard-Log "ERROR: sin checksum para opencode-$Platform"
    exit 1
  }

  $Expected = ($ExpectedLine -split '\s+')[0].ToLower()
  $Actual = (Get-FileHash -LiteralPath $Tmp -Algorithm SHA256).Hash.ToLower()
  if ($Actual -ne $Expected) {
    Guard-Log "ERROR: SHA256 no coincide; binario descartado"
    Remove-Item -LiteralPath $Tmp, $ShaTmp -Force -ErrorAction SilentlyContinue
    exit 1
  }

  # Reemplazo con reintentos por si opencode.exe está abierto en estos segundos.
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
    Guard-Log "ERROR: no se pudo reemplazar $Bin (proceso en uso?)"
    exit 1
  }

  Set-Content -LiteralPath $Marker -Value $Actual -NoNewline
  Guard-Log "skill-toggle reinstalado OK ($Platform, sha256 $Actual)"
} finally {
  Remove-Item -LiteralPath $ShaTmp -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Tmp -Force -ErrorAction SilentlyContinue
}