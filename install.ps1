#Requires -Version 5.1
<#
  Instala opencode + skill-toggle (build personalizada del binario de opencode) en Windows.

  Uso:
    powershell -ExecutionPolicy Bypass -c "irm https://github.com/BenReynor/opencode-skill-toggle/releases/latest/download/install.ps1 | iex"

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
$Url = "https://github.com/$Repo/releases/latest/download/opencode-$Platform"

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

Write-Step "Descargando: $Url"
$Tmp = Join-Path $BinDir "opencode.download"
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
  & curl.exe -fsSL $Url -o $Tmp
  if ($LASTEXITCODE -ne 0) { throw "curl no pudo descargar $Url (exit $LASTEXITCODE)" }
} else {
  Invoke-WebRequest -Uri $Url -OutFile $Tmp -UseBasicParsing
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
Write-Host ""

Write-Host @"
Aviso importante:
  - Esta es una build personalizada (no oficial). Mantiene tu opencode.db real.
  - Configura "autoupdate": false en opencode.json para que no la reemplace
    el instalador oficial.
  - Al ser un binario sin firma, Windows SmartScreen puede mostrarte un aviso
    la primera vez: pulsa "Más información" > "Ejecutar de todas formas".
  - Reinicia opencode para que el binario nuevo quede activo.
"@