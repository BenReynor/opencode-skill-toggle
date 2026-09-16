#Requires -Version 5.1
<#
  Instala opencode + skill-toggle (build personalizada del binario de opencode) en Windows.

  Uso:
    powershell -ExecutionPolicy Bypass -c "irm https://github.com/BenReynor/opencode-skill-toggle/releases/download/latest/install.ps1 | iex"

  Opcional:
    $env:GH_REPO = "tudusuario/opencode-skill-toggle"  antes de ejecutar.

  Descarga el binario de la plataforma actual desde el release "latest",
  respalda la instalación anterior y reemplaza %USERPROFILE%\.opencode\bin\opencode.exe.
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

# --- Detectar plataforma ----------------------------------------------------
$arch = $env:PROCESSOR_ARCHITECTURE
if (-not $arch) {
  $arch = $env:PROCESSOR_ARCHITEW6432
}
switch ($arch) {
  "AMD64" { $Platform = "windows-x64" }
  "ARM64" {
    Write-Warning "Windows ARM64: no publicamos binario nativo arm64; se usa windows-x64 (emulación en Windows 11 ARM)."
    $Platform = "windows-x64"
  }
  default { throw "Plataforma no soportada: $arch" }
}
Write-Step "Plataforma: $Platform"

# --- Obtener el binario -----------------------------------------------------
$BinDir = Join-Path $HOME ".opencode\bin"
$Final = Join-Path $BinDir "opencode.exe"
$Url = "https://github.com/$Repo/releases/download/latest/opencode-$Platform"

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

Write-Step "Descargando: $Url"
$Tmp = Join-Path $BinDir "opencode.download"
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
  & curl.exe -fsSL $Url -o $Tmp
  if ($LASTEXITCODE -ne 0) { throw "curl no pudo descargar $Url (exit $LASTEXITCODE)" }
} else {
  Invoke-WebRequest -Uri $Url -OutFile $Tmp -UseBasicParsing
}

# --- Verificación SHA256 ----------------------------------------------------
$ShaUrl = "https://github.com/$Repo/releases/download/latest/SHA256SUMS"
$ShaTmp = Join-Path $BinDir "opencode-sha256.download"
Write-Step "Verificando SHA256 contra $ShaUrl"
try {
  if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    & curl.exe -fsSL $ShaUrl -o $ShaTmp
    if ($LASTEXITCODE -ne 0) { throw "curl no pudo descargar $ShaUrl (exit $LASTEXITCODE)" }
  } else {
    Invoke-WebRequest -Uri $ShaUrl -OutFile $ShaTmp -UseBasicParsing
  }
  # El formato de SHA256SUMS es "<hash>  opencode-<platform>"
  $ExpectedLine = Get-Content $ShaTmp | Where-Object { $_ -match "(?i)opencode-$Platform\s*$" } | Select-Object -First 1
  if (-not $ExpectedLine) {
    Write-Warning "No hay checksum para opencode-$Platform; se continúa sin verificar."
  } else {
    $Expected = ($ExpectedLine -split '\s+')[0]
    $Actual = (Get-FileHash -Path $Tmp -Algorithm SHA256).Hash.ToLower()
    if ($Actual -ne $Expected.ToLower()) {
      Remove-Item -Force $Tmp, $ShaTmp -ErrorAction SilentlyContinue
      throw "Verificación SHA256 falló para opencode-$Platform. Esperado: $Expected. Obtenido: $Actual. El binario se descartó por posible manipulación."
    }
    Write-Step "SHA256 verificado correctamente"
  }
} finally {
  if (Test-Path $ShaTmp) { Remove-Item -Force $ShaTmp }
}

# --- Backup del binario actual ----------------------------------------------
if (Test-Path $Final) {
  $Backup = "$Final.bak"
  if (-not (Test-Path $Backup)) {
    Copy-Item $Final $Backup -Force
    Write-Step "Backup guardado: $Backup"
  } else {
    Write-Step "Backup existente: $Backup (no se sobreescribe)"
  }
}

# --- Instalar ---------------------------------------------------------------
Move-Item -Force $Tmp $Final
Write-Step "Instalado: $Final"

# --- Marcador para el guardián ---
$ActualHash = (Get-FileHash -LiteralPath $Final -Algorithm SHA256).Hash.ToLower()
Set-Content -LiteralPath "$Final.sha256" -Value $ActualHash -NoNewline

# --- Guardián anti-borrado (Task Scheduler) --------------------------------
if ($env:TOGGLE_GUARD -ne "0") {
  $Guard = Join-Path $HOME ".opencode\toggle-guard.ps1"
  if ($PSScriptRoot) {
    $LocalGuard = Join-Path $PSScriptRoot "scripts\toggle-guard.ps1"
    if (Test-Path -LiteralPath $LocalGuard) {
      Copy-Item -LiteralPath $LocalGuard -Destination $Guard -Force
    } else {
      Write-Step "Descargando toggle-guard.ps1"
      Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/latest/toggle-guard.ps1" -OutFile $Guard -UseBasicParsing
    }
  } else {
    Write-Step "Descargando toggle-guard.ps1"
    Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/latest/toggle-guard.ps1" -OutFile $Guard -UseBasicParsing
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
    Write-Step "Guardián anti-borrado activado (Task Scheduler: $TaskName)"
    Write-Step "  - log: $(Join-Path $HOME '.opencode\toggle-guard.log')"
    Write-Step "  - desactivar: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
  } catch {
    Write-Warning "No se pudo registrar el guardián: $($_.Exception.Message)"
  }
} else {
  Write-Step "Guardián anti-borrado no instalado (TOGGLE_GUARD=0)"
}

Write-Host ""
Write-Host @"
Aviso importante:
  - Esta es una build personalizada (no oficial). Mantiene tu opencode.db real.
  - Al descargar de GitHub Releases, el binario se verifica contra SHA256SUMS.
  - Guardián anti-borrado ya configurado por defecto: restaura el toggle si la
    actualización oficial lo reemplaza. (Alternativa: "autoupdate": false en
    opencode.json desactiva el autoupdate oficial; ver README / Actualizaciones.)
  - Al ser un binario sin firma, Windows SmartScreen puede mostrarte un aviso
    la primera vez: pulsa "Más información" > "Ejecutar de todas formas".
  - Reinicia opencode para que el binario nuevo quede activo.
"@