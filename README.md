# opencode-skill-toggle

Build personalizada de **opencode** que añade un **toggle de skills real y persistente**.

Con el toggle puedes tener instaladas todas las skills que quieras, pero **usar solo las que actives**: las deshabilitadas se quitan del prompt del sistema, la herramienta `skill()` las rechaza, y el estado sobrevive reinicios. Así evitas sobrecargar opencode — igual que el toggle de MCP, pero para skills.

## Qué cambia vs opencode oficial

| | Oficial | Este build |
|---|---|---|
| Toggle en el diálogo (`/skill-toggle`) | no | sí |
| Deshabilitada → fuera del system prompt | — | sí |
| `skill()` rechaza deshabilitadas | — | sí (`NotFoundError`) |
| Estado persistente (sobrevive reinicio) | — | sí (`~/.local/share/opencode/skills-toggle.json`) |

También incluye el fix de compilación local (`splitting` configurable) necesario para generar binarios estables con bun.

## Instalar

Descarga e instala desde los Releases de este repo:

```bash
curl -sL https://github.com/BenReynor/opencode-skill-toggle/releases/latest/download/install.sh | bash
```

o manualmente:

```bash
# 1. descarga el binario de tu plataforma desde releases/latest
# 2. (opcional) guarda backup del actual
cp ~/.opencode/bin/opencode ~/.opencode/bin/opencode.bak
# 3. reemplaza
cp opencode-linux-x64 ~/.opencode/bin/opencode
chmod +x ~/.opencode/bin/opencode
```

> **Importante:** desactiva el autoupdate en tu config para que el instalador
> oficial no reemplace este binario:
> `"autoupdate": false` en `opencode.json`.

Reinicia opencode. Usa el diálogo `/skill-toggle` (o `/mcp`) para activar/desactivar.

## Uso del toggle

- Abre el diálogo `skill-toggle` desde la TUI.
- `✓ Enabled` / `○ Disabled`.
- Las deshabilitadas desaparecen del `available_skills` del modelo y `skill()`
  responde: _«Skill not found. Available skills: ...»_.
- El estado se guarda en `~/.local/share/opencode/skills-toggle.json`.

## Compilar desde fuente

Requisitos: [bun](https://bun.sh) (≥1.2).

```bash
./build.sh              # compila la versión anclada que valida el toggle (v1.18.30)
./build.sh latest       # compila la última versión publicada (puede requerir actualizar patches)
./build.sh 1.18.30      # compila una versión concreta
```

El binario queda en `dist/opencode-linux-x64` (y una copia `opencode-<version>-toggle-linux-x64`).

### Compilar a mano

```bash
git clone https://github.com/anomalyco/opencode.git /tmp/opencode-src
cd /tmp/opencode-src
git checkout v1.18.30
git apply /ruta/a/patches/00-skill-toggle.patch  # el toggle
git apply /ruta/a/patches/01-build-local-fix.patch # fix de build
bun install --frozen-lockfile
cd packages/opencode
OPENCODE_CHANNEL=latest OPENCODE_VERSION=1.18.30 SPLIT=0 \
  bun run build --single --skip-embed-web-ui
```

El binario sale en `dist/opencode-linux-x64/bin/opencode`.

## Releases automáticos (CI)

El workflow `.github/workflows/build-and-release.yml`:

- Revisa los releases de `anomalyco/opencode` cada día (04:30 UTC) y con
  `workflow_dispatch` manual.
- Si hay una versión nueva **no publicada aún**, clona, aplica los patches,
  compila (`linux-x64` y `linux-arm64`) y publica:
  - release versionado `toggle-<versión>` con `opencode-<versión>-toggle-<plataforma>`
  - assets `opencode-<plataforma>` en el release `latest` (para el instalador)
- Si un patch no aplica en una versión nueva, abre un issue avisando.

Plataformas: Linux x64 y arm64. (macOS/Windows: usa `./build.sh` local.)

## Notas

- La DB es la misma de opencode oficial (`opencode.db`, canal `latest`) — no se
  pierden sesiones.
- Esto no reemplaza un plugin: es una modificación del núcleo (server + TUI),
  por eso se distribuye como binario.
- Los commits corresponden a la rama de trabajo (2 commits originales + el fix
  de persistencia/bloqueo real).