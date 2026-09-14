# opencode-skill-toggle

Una versión de **opencode** con un interruptor (toggle) para activar o
desactivar **cada skill por separado**, y que recuerda tu elección.

Mantienes instaladas todas las skills que quieras, pero solo se cargan las que
tienes activadas: las desactivadas no aparecen en las sugerencias del modelo y
se rechazan al pedirlas. Así evitas saturar opencode cuando tienes muchas skills
instaladas.

## Qué hace

| | opencode oficial | Esta versión |
|---|---|---|
| Activar / desactivar una skill | — | ✓ |
| La desactivada desaparece del entorno del modelo | — | ✓ |
| Se rechaza si la pides desactivada | — | ✓ |
| Recuerda tu elección entre reinicios | — | ✓ |

## Instalar

### Con un solo comando

**Linux / macOS**

```bash
curl -sL https://github.com/BenReynor/opencode-skill-toggle/releases/latest/download/install.sh | bash
```

**Windows (PowerShell)**

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/BenReynor/opencode-skill-toggle/releases/latest/download/install.ps1 | iex"
```

Estos comandos descargan el binario adecuado a tu sistema, lo instalan y crean
una copia de seguridad de la instalación anterior por si quieres volver.

### Manual

1. Ve a [Releases](https://github.com/BenReynor/opencode-skill-toggle/releases)
   y descarga el archivo que corresponda a tu sistema:
   `opencode-linux-x64`, `opencode-linux-arm64`, `opencode-linux-*-musl`,
   `opencode-linux-x64-baseline`, `opencode-darwin-x64`, `opencode-darwin-arm64`
   o `opencode-windows-x64`.
2. Sustituye el binario existente de opencode por el descargado:
   - Linux/macOS: reemplaza `~/.opencode/bin/opencode` (recuerda `chmod +x`).
   - Windows: reemplaza `%USERPROFILE%\.opencode\bin\opencode.exe`.
3. Si lo deseas, guarda antes una copia del anterior con otro nombre.

> **Nota sobre binarios sin firmar**: esta build no está firmada. En macOS,
> Gatekeeper puede bloquear la primera ejecución: usa _clic derecho > Abrir_ o
> `xattr -dr com.apple.quarantine opencode`. En Windows,
> SmartScreen avisará la primera vez: pulsa _Más información > Ejecutar de todas formas_.

### ¿Qué binario Linux elijo?

- `linux-x64` / `linux-arm64`: para la mayoría de distros (glibc) — Ubuntu,
  Debian, Fedora, Arch, Mint, etc.
- `linux-x64-musl` / `linux-arm64-musl`: para distros con **musl** (p.ej. Alpine).
- `linux-x64-baseline`: para CPUs muy antiguas **sin AVX2**.

### Importante: desactiva la actualización automática

Para que el instalador oficial de opencode no reemplace esta versión, añade
esto a tu archivo de configuración (`opencode.json`):

```json
{
  "autoupdate": false
}
```

Reinicia opencode cuando termines.

## Cómo se usa

Abre el diálogo de opencode y escribe:

```
/skill-toggle
```

Selecciona la skill que quieras y actívala o desactívala:

- `✓ Enabled` — la skill está activa.
- `○ Disabled` — la skill está desactivada (no se carga ni se puede pedir).

Tu elección se guarda en disco y se mantiene al reiniciar opencode.

## Preguntas frecuentes

- **¿Pierdo mis conversaciones o ajustes?** No. Esta versión usa la misma base
  de datos que opencode oficial; no se pierde nada al cambiarla.

- **¿Es una Skill de opencode?** No exactamente: es una mejora del propio
  opencode (el servidor y la interfaz), por eso se distribuye como binario y no
  como un plugin.

- **¿Windows / macOS?** Funciona en Linux, macOS y Windows (CLI de terminal). Para
  Windows usa el instalador PowerShell descrito antes; macOS usa el mismo
  instalador de `curl | bash` o el binario `opencode-darwin-*`.

## Actualizaciones

Este repositorio se revisa automáticamente: cuando opencode publica una versión
nueva, se compila de nuevo con esta mejora y se publica aquí. Así tienes lo
último de opencode **con** el toggle, sin hacer nada.

## ¿Problemas?

Abre un [issue](https://github.com/BenReynor/opencode-skill-toggle/issues) y
cuéntanos qué pasa. Se agradece indicar tu sistema operativo y la versión.

---

*Build no oficial de opencode. opencode es de sus autores; esta versión añade
la función de interruptor de skills.*
