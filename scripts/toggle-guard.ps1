#Requires -Version 5.1
<#
  toggle-guard.ps1 — Guardián del skill-toggle para Windows.

  Si opencode.exe fue reemplazado (por el autoupdate oficial o por una
  instalación manual del binario limpio), reinstala la build con skill-toggle
  descargándola del release versionado más nuevo y verificando el SHA256.

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
$TagCache = Join-Path $HOME ".opencode\.toggle-guard-tag"

# Cada build se publica en un tag único (toggle-X.Y.Z o toggle-X.Y.Z-r<build>):
# su contenido nunca cambia, así que la descarga nunca mezcla bins viejos del
# CDN (lo que sí ocurriría con "latest", que se sobrescribe). Resolución con
# caché de 6 horas para no agotar el rate limit de la API.
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

Guard-Log "binario distinto al marcado: el autoupdate oficial pudo reemplazarlo; reinstalo skill-toggle"

$Tmp = Join-Path $env:TEMP "opencode-toggle.download"
$ShaTmp = Join-Path $env:TEMP "opencode-toggle.sha"

try {
  Invoke-WebRequest -Uri "$ReleaseBase/opencode-$Platform" -OutFile $Tmp -UseBasicParsing
  Invoke-WebRequest -Uri "$ReleaseBase/SHA256SUMS" -OutFile $ShaTmp -UseBasicParsing

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

  # Limpieza de residuos de versiones anteriores (backups .bak / temporales).
  $Cleanup = Join-Path $HOME ".opencode\toggle-cleanup.ps1"
  if (Test-Path -LiteralPath $Cleanup) {
    & $Cleanup | Out-Null
  }
} finally {
  Remove-Item -LiteralPath $ShaTmp -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Tmp -Force -ErrorAction SilentlyContinue
}