# ✨ opencode-skill-toggle

![CI](https://github.com/BenReynor/opencode-skill-toggle/actions/workflows/build-and-release.yml/badge.svg)
![Release](https://img.shields.io/github/v/release/BenReynor/opencode-skill-toggle)
![Plataformas](https://img.shields.io/badge/plataformas-Linux%20·%20macOS%20·%20Windows-informational)

> 🎚️ **opencode con un interruptor para cada skill.** Activa o desactiva las
> skills por separado y él **recuerda tu decisión** entre reinicios.

Mantén instaladas todas las skills que quieras, pero solo se cargan las que tienes
**activadas**. Las desactivadas dejan de saturar las sugerencias del modelo y se
rechazan si alguien intenta pedirlas.

---

## 🚀 Qué hace

| Emoji | Función |
|-------|---------|
| 🎚️ | Enciende y apaga **cada skill por separado** |
| 🧹 | Las skills desactivadas **desaparecen del entorno del modelo** |
| 🚫 | Si pides una skill desactivada, **se rechaza** limpiamente |
| 🧠 | Tu elección **se guarda en disco** y sobrevive a los reinicios |
| 💾 | Usa la misma base de datos: **no pierdes conversaciones ni ajustes** |
| 🛡️ | Guardián que restaura el toggle si la actualización oficial lo pisa (Linux · macOS · Windows) |
| 🖥️ | Funciona en **Linux, macOS y Windows** (CLI de terminal) |

---

## 📥 Instalación

### 🟢 Linux / macOS — un solo comando

```bash
curl -sL https://github.com/BenReynor/opencode-skill-toggle/releases/download/latest/install.sh | bash
```

### 🔵 Windows — un solo comando (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/BenReynor/opencode-skill-toggle/releases/download/latest/install.ps1 | iex"
```

> El instalador detecta tu plataforma, descarga el binario adecuado, **verifica su
> SHA256** y crea una copia de seguridad de la instalación anterior. El reemplazo
> es **atómico**: puedes reinstalar incluso con opencode abierto (el proceso en
> marcha conserva su binario viejo; las sesiones nuevas usan el nuevo).
>
> En **Linux, macOS y Windows** el instalador deja activo por defecto el 🛡️
> **guardián anti-borrado** (systemd / launchd / Task Scheduler): si el autoupdate
> oficial reemplaza tu binario, el toggle se restaura solo en segundo plano
> (desactivable con `TOGGLE_GUARD=0`).

### 📦 Manual

1. Ve a [Releases](https://github.com/BenReynor/opencode-skill-toggle/releases).
2. Descarga tu binario:

   | Sistema | Archivo |
   |---------|---------|
   | 🐧 Linux x64 | `opencode-linux-x64` |
   | 🐧 Linux ARM | `opencode-linux-arm64` |
   | 🐧 Linux musl | `opencode-linux-*-musl` |
   | 🐧 Linux CPUs antiguas | `opencode-linux-x64-baseline` |
   | 🍎 macOS Intel | `opencode-darwin-x64` |
   | 🍎 macOS Apple Silicon | `opencode-darwin-arm64` |
   | 🪟 Windows x64 | `opencode-windows-x64` |

3. Sustituye el binario de opencode:
   - **Linux/macOS**: `~/.opencode/bin/opencode` (recuerda `chmod +x`).
   - **Windows**: `%USERPROFILE%\.opencode\bin\opencode.exe`.
4. Opcional: guarda antes una copia del anterior.

> **🔓 Binarios sin firmar**: en macOS, Gatekeeper puede bloquear la primera
> ejecución (_clic derecho > Abrir_ o `xattr -dr com.apple.quarantine opencode`).
> En Windows, SmartScreen avisará la primera vez (_Más información > Ejecutar de
> todas formas_).

### 🤔 ¿Qué binario Linux elijo?

- **`linux-x64` / `linux-arm64`** — la mayoría de distros (glibc): Ubuntu, Debian,
  Fedora, Arch, Mint…
- **`linux-x64-musl` / `linux-arm64-musl`** — distros con **musl** (p. ej. Alpine).
- **`linux-x64-baseline`** — CPUs muy antiguas **sin AVX2**.

---

## 🕹️ Cómo se usa

Abre el diálogo de opencode y escribe:

```
/skill-toggle
```

Selecciona la skill que quieras y actívala o desactívala:

- ✅ **Enabled** — la skill está activa y disponible.
- ⭕ **Disabled** — la skill está desactivada; no se carga ni se puede pedir.

Tu elección se guarda al instante en disco y se mantiene al reiniciar. 🔁

### 🔌 Estado desde la API (avanzado)

Si ejecutas `opencode serve`, el toggle también es consultable vía HTTP, útil
para scripts y CI:

| Endpoint | Método | Efecto |
|----------|--------|--------|
| `/skill/status` | GET | Estado de cada skill (enabled/disabled) |
| `/skill/:name/enable` | POST | Activa la skill al instante |
| `/skill/:name/disable` | POST | La desactiva al instante y persiste |

El diálogo `/skill-toggle` de la interfaz hace exactamente lo mismo.

---

## ❓ Preguntas frecuentes

- **¿Pierdo mis conversaciones o ajustes?**
  No. Esta versión usa la misma base de datos de opencode; no se pierde nada.

- **¿Es una Skill de opencode?**
  No exactamente: es una mejora del propio opencode (servidor e interfaz), por eso
  se distribuye como binario y no como plugin.

- **¿Funciona en Windows / macOS?**
  Sí. Linux, macOS y Windows, todo desde el terminal. En Windows usa el instalador
  PowerShell; en macOS el de `curl | bash` o el binario `opencode-darwin-*`.

- **¿Puedo desactivar todas las skills?**
  Sí, cada skill se gestiona de forma independiente. Puedes dejarlas todas
  apagadas o solo las que no uses.

- **¿El guardián funciona también en macOS / Windows?**
  Sí. macOS usa un LaunchAgent (launchd, cada 15 min) y Windows un Scheduled
  Task (cada 15 min y al iniciar sesión); los activa `install.sh` / `install.ps1`
  automáticamente.

---

## 🔄 Actualizaciones

Este repositorio se reconstruye solo: cuando opencode publica una versión nueva,
se compila de nuevo con el interruptor y se publica en `latest`. Así siempre
tienes lo último **con** el toggle.

La actualización oficial reemplaza `~/.opencode/bin/opencode` (o `opencode.exe`)
por el binario limpio. Para que el toggle nunca se pierda, el instalador deja
**ya activo por defecto** el guardián anti-borrado:

### 🛡️ Guardián anti-borrado (ya viene configurado)

Restaura el toggle solo, en segundo plano, si el binario fue reemplazado:

- Tras instalar deja un **marcador** con el SHA-256 del binario con toggle
  (un `opencode.sha256` junto al binario).
- El guardián (`toggle-guard.sh` en Linux/macOS, `toggle-guard.ps1` en Windows)
  compara ese marcador con el binario actual; si difiere, descarga la build con
  toggle de `latest`, **verifica su SHA256** y la reinstala (reemplazo atómico,
  sin cortar lo que esté en marcha).
- Qué lo dispara según el sistema:

  | Sistema | Mecanismo |
  |---------|-----------|
  | Linux | systemd `--user`: `.path` (inotify) + `.timer` cada 15 min |
  | macOS | launchd LaunchAgent cada 15 min |
  | Windows | Task Scheduler cada 15 min y al iniciar sesión |

> **No deja ningún proceso en espera**: no hay daemon propio. Lo vigila el
> planificador del sistema (ya residente) y solo ejecuta el guardián un instante
> cuando hay algo que hacer.

Comprobar su estado y desactivarlo:

```bash
# estado (Linux)
systemctl --user status opencode-toggle-guard.timer

# desactivar (Linux)
systemctl --user disable --now opencode-toggle-guard.path opencode-toggle-guard.timer

# desactivar (macOS)
launchctl unload -w ~/Library/LaunchAgents/com.opencode.skill-toggle-guard.plist

# desactivar (Windows, PowerShell)
Unregister-ScheduledTask -TaskName 'opencode-skill-toggle-guard' -Confirm:$false

# que los instaladores no lo vuelvan a crear
TOGGLE_GUARD=0 ./install.sh
```

Log de actividad: `~/.opencode/toggle-guard.log`.

**Opción alternativa — desactivar el autoupdate oficial**

Si prefieres que el instalador oficial jamás toque tu binario (con esto el
guardián ya no es necesario, aunque tampoco estorba), desactiva el autoupdate en
`opencode.json`:

```json
{
  "autoupdate": false
}
```

Para actualizar entonces, vuelve a ejecutar el comando de instalación:
descargará la última build con toggle desde nuestro release `latest`.

---

## 🔒 Seguridad

- **🔐 SHA256 verificado**: cada release publica `SHA256SUMS`; el instalador
  comprueba el binario antes de instalarlo y aborta si no coincide.
- **🏭 Compilado en GitHub Actions**: los binarios se crean en CI desde el código
  de upstream + parches, no se suben binarios hechos a mano.
- **🔗 Actions pineadas a SHA**: versión concreta y fija de `actions/checkout` y
  `setup-bun`.
- **🔑 Sin secretos**: el workflow solo usa `GITHUB_TOKEN` con permisos mínimos.
- Puedes verificar cualquier binario con:
  `shasum -a 256 opencode` (macOS) o `sha256sum opencode` (Linux).

---

## 🆘 ¿Problemas?

Abre un [issue](https://github.com/BenReynor/opencode-skill-toggle/issues) e indica
tu sistema operativo y la versión que usas. ¡Gracias por reportar! 🙌