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
| 🛡️ | Guardián opcional que restaura el toggle si la actualización oficial lo pisa |
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
> En **Linux con systemd**, además queda activo por defecto el 🛡️ **guardián
> anti-borrado**: si el autoupdate oficial reemplaza tu binario, el toggle se
> restaura solo en segundo plano (desactivable con `TOGGLE_GUARD=0`).

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

### ⚠️ Desactiva la actualización automática

Para que el instalador oficial no reemplace esta versión, añade a `opencode.json`:

```json
{
  "autoupdate": false
}
```

Reinicia opencode cuando termines. ✅

> 🛡️ **Otra vía**: prefiere mantener el autoupdate oficial y dejar que el
> guardián anti-borrado (sección más abajo) restaure el toggle solo.

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

- **¿El guardián anti-borrado deja un proceso en segundo plano de espera?**
  No. No hay ningún daemon propio: lo vigila el `systemd --user` que ya corre en
  tu sesión (inotify + un timer). Solo se lanza `toggle-guard.sh` un instante
  cuando el binario cambia — y si no hay nada que hacer, sale en milisegundos.

- **¿El guardián funciona también en macOS / Windows?**
  Todavía no: el guardián automático está disponible en **Linux con systemd**.
  macOS (launchd) y Windows (Task Scheduler) pueden usar el mismo
  `toggle-guard.sh`, aún por integrar en el instalador.

---

## 🔄 Actualizaciones

Este repositorio se revisa automáticamente: cuando opencode publica una versión
nueva, se compila de nuevo con el interruptor y se publica aquí. Así siempre
tienes lo último **con** el toggle, sin hacer nada.

¿Cómo evitas que la actualización oficial **borre** tu toggle?

1. **`autoupdate: false`** en `opencode.json` (sección de arriba). El instalador
   oficial ya no sobreescribirá tu binario.
2. **Para actualizar de verdad**, vuelve a ejecutar el mismo comando de
   instalación: descarga la última build con toggle desde nuestro release
   `latest`. Es lo único que necesitas recordar.

> El comando oficial `opencode upgrade` sí reemplaza `~/.opencode/bin/opencode`
> por el binario oficial limpio; por eso se desactiva. Nuestra build aplica el
> mismo toggle a las versiones nuevas, así que actualizar desde este repo no
> pierde nada.

### 🛡️ Guardián anti-borrado (Linux)

¿Prefieres **mantener el autoupdate oficial** y que el toggle se restaure solo?
El instalador activa por defecto un guardián basado en `systemd --user`:

- Tras instalar deja un **marcador** con el SHA-256 del binario con toggle
  (`~/.opencode/bin/opencode.sha256`).
- `~/.opencode/toggle-guard.sh` se dispara cuando el binario cambia (`.path` con
  inotify del kernel + `.timer` de respaldo cada 15 min).
- Si el autoupdate oficial o `opencode upgrade` reemplazan tu binario, el
  guardián descarga la build con toggle de `latest`, **verifica su SHA256** y la
  restaura al instante (reemplazo atómico, sin cortar lo que esté en marcha).

> **No deja ningún proceso en espera.** No existe un daemon propio: lo vigila el
> propio `systemd --user` (ya residente en tu sesión) con inotify + un timer, y
> solo ejecuta el script un instante cuando hay que actuar. Si no hay nada que
> hacer, el chequeo dura milisegundos.

Se desactiva con:

```bash
TOGGLE_GUARD=0 ./install.sh        # no instalar el guardián
systemctl --user disable --now opencode-toggle-guard.path opencode-toggle-guard.timer
```

Log de actividad: `~/.opencode/toggle-guard.log`.

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

---

*Build personal de opencode con la función de interruptor de skills.*