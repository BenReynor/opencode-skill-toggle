# ✨ opencode-skill-toggle

![CI](https://github.com/BenReynor/opencode-skill-toggle/actions/workflows/build-and-release.yml/badge.svg)
![Release](https://img.shields.io/github/v/release/BenReynor/opencode-skill-toggle)
![Platforms](https://img.shields.io/badge/platforms-Linux%20·%20macOS%20·%20Windows-informational)

> 🎚️ **opencode with a toggle for every skill.** Enable or disable each skill
> independently and it **remembers your choice** between restarts.

Keep all the skills you want installed, but only the ones you have **enabled**
are actually loaded. Disabled skills stop cluttering the model's suggestions and
are rejected if someone tries to invoke them.

---

## 🚀 What it does

| Emoji | Feature |
|-------|---------|
| 🎚️ | Turns **each skill on and off independently** |
| 🧹 | Disabled skills **disappear from the model's environment** |
| 🚫 | Asking for a disabled skill **is rejected** cleanly |
| 🧠 | Your choice **is saved to disk** and survives restarts |
| 💾 | Uses the same database: **no lost conversations or settings** |
| 🛡️ | Guard that restores the toggle if the official update overwrites it (Linux · macOS · Windows) |
| 🖥️ | Works on **Linux, macOS and Windows** (CLI) |

---

## 📥 Installation

### 🟢 Linux / macOS — a single command

```bash
curl -sL https://github.com/BenReynor/opencode-skill-toggle/releases/download/latest/install.sh | bash
```

### 🔵 Windows — a single command (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/BenReynor/opencode-skill-toggle/releases/download/latest/install.ps1 | iex"
```

> The installer detects your platform, downloads the proper binary, **verifies its
> SHA256** and makes a backup of the previous installation. The replacement is
> **atomic**: you can reinstall even while opencode is running (the running process
> keeps its old binary; new sessions use the new one).
>
> On **Linux, macOS and Windows** the installer leaves the 🛡️ **anti-overwrite
> guard** enabled by default (systemd / launchd / Task Scheduler): if the official
> autoupdate replaces your binary, the toggle is restored automatically in the
> background (disable it with `TOGGLE_GUARD=0`).

### 📦 Manual install

1. Go to [Releases](https://github.com/BenReynor/opencode-skill-toggle/releases).
2. Download your binary:

   | System | File |
   |---------|---------|
   | 🐧 Linux x64 | `opencode-linux-x64` |
   | 🐧 Linux ARM | `opencode-linux-arm64` |
   | 🐧 Linux musl | `opencode-linux-*-musl` |
   | 🐧 Old Linux CPUs | `opencode-linux-x64-baseline` |
   | 🍎 macOS Intel | `opencode-darwin-x64` |
   | 🍎 macOS Apple Silicon | `opencode-darwin-arm64` |
   | 🪟 Windows x64 | `opencode-windows-x64` |

3. Replace the opencode binary:
   - **Linux/macOS**: `~/.opencode/bin/opencode` (remember `chmod +x`).
   - **Windows**: `%USERPROFILE%\.opencode\bin\opencode.exe`.
4. Optional: keep a copy of the previous one before replacing.

> **🔓 Unsigned binaries**: on macOS, Gatekeeper may block the first run
> (_right-click > Open_ or `xattr -dr com.apple.quarantine opencode`). On Windows,
> SmartScreen will warn the first time (_More info > Run anyway_).

### 🤔 Which Linux binary should I pick?

- **`linux-x64` / `linux-arm64`** — most distros (glibc): Ubuntu, Debian, Fedora,
  Arch, Mint…
- **`linux-x64-musl` / `linux-arm64-musl`** — distros with **musl** (e.g. Alpine).
- **`linux-x64-baseline`** — very old CPUs **without AVX2**.

---

## 🕹️ How to use

Open the opencode dialog and type:

```
/skill-toggle
```

Select the skill you want and enable or disable it:

- ✅ **Enabled** — the skill is active and available.
- ⭕ **Disabled** — the skill is off; it is neither loaded nor invocable.

Your choice is saved to disk instantly and persists across restarts. 🔁

### 🔌 Query the state via the API (advanced)

If you run `opencode serve`, the toggle is also reachable over HTTP, handy for
scripts and CI:

| Endpoint | Method | Effect |
|----------|--------|--------|
| `/skill/status` | GET | State of each skill (enabled/disabled) |
| `/skill/:name/enable` | POST | Enables the skill instantly |
| `/skill/:name/disable` | POST | Disables it instantly and persists |

The `/skill-toggle` dialog does exactly the same thing.

---

## ❓ FAQ

- **Do I lose my conversations or settings?**
  No. This version uses the same opencode database; nothing is lost.

- **Is it an opencode Skill?**
  Not exactly: it is an enhancement of opencode itself (server and UI), which is
  why it ships as a binary rather than a plugin.

- **Does it work on Windows / macOS?**
  Yes. Linux, macOS and Windows, all from the terminal. On Windows use the
  PowerShell installer; on macOS the `curl | bash` installer or the
  `opencode-darwin-*` binary.

- **Can I disable all skills?**
  Yes, each skill is managed independently. You can leave them all off or only
  the ones you do not use.

- **Does the guard also work on macOS / Windows?**
  Yes. macOS uses a LaunchAgent (launchd, every 15 min) and Windows a Scheduled
  Task (every 15 min and at logon); `install.sh` / `install.ps1` set them up
  automatically.

---

## 🔄 Updates

This repository self-rebuilds: whenever opencode releases a new version, it is
rebuilt with the toggle and published to a versioned release. That way you always
get the latest version **with** the toggle.

> Each build is published to a **unique tag** (`toggle-<version>` or
> `toggle-<version>-r<build>`): the content of every release never changes, so the
> installers and the guard always download the correct binary with no risk of
> mixing old/new copies in GitHub's cache (they resolve the most recent `toggle-*`
> tag through the GitHub API).

The official update replaces `~/.opencode/bin/opencode` (or `opencode.exe`) with
the clean binary. To make sure the toggle is never lost, the installer leaves the
**anti-overwrite guard enabled by default**:

### 🛡️ Anti-overwrite guard (already set up)

It restores the toggle silently, in the background, if the binary was replaced:

- After installing it leaves a **marker** with the SHA-256 of the toggle binary
  (an `opencode.sha256` next to the binary).
- The guard (`toggle-guard.sh` on Linux/macOS, `toggle-guard.ps1` on Windows)
  compares that marker with the current binary; if they differ, it downloads the
  toggle build from the newest versioned release, **verifies its SHA256** and
  reinstalls it (atomic replacement, without interrupting what is running).
- What triggers it on each system:

  | System | Mechanism |
  |---------|-----------|
  | Linux | systemd `--user`: `.path` (inotify) + `.timer` every 15 min |
  | macOS | launchd LaunchAgent every 15 min |
  | Windows | Task Scheduler every 15 min and at logon |

> **No process stays waiting**: there is no daemon of its own. The system
> scheduler (already resident) does the watching and only runs the guard briefly
> when there is something to do.

Check its status and disable it:

```bash
# status (Linux)
systemctl --user status opencode-toggle-guard.timer

# disable (Linux)
systemctl --user disable --now opencode-toggle-guard.path opencode-toggle-guard.timer

# disable (macOS)
launchctl unload -w ~/Library/LaunchAgents/com.opencode.skill-toggle-guard.plist

# disable (Windows, PowerShell)
Unregister-ScheduledTask -TaskName 'opencode-skill-toggle-guard' -Confirm:$false

# so that the installers don't re-create it
TOGGLE_GUARD=0 ./install.sh
```

Activity log: `~/.opencode/toggle-guard.log`.

### 🧹 Automatic residue cleanup

On every install/restore, leftovers from previous versions are removed
(`~/.opencode/bin/opencode.bak`, `opencode.<version>.bak`, `*.download`/`*.tmp`
temporary files), so hundreds of MB never pile up. Only the active binary and its
`opencode.sha256` marker are kept.

```bash
# run the cleanup manually (dry run and real run)
TOGGLE_CLEANUP_DRY_RUN=1 bash ~/.opencode/toggle-cleanup.sh   # list only
bash ~/.opencode/toggle-cleanup.sh                            # actually clean

# keep a single .bak of the previous version
TOGGLE_CLEANUP_KEEP_BACKUP=1 bash ~/.opencode/toggle-cleanup.sh
```

The installer and the guard run it automatically on all three platforms
(`toggle-cleanup.sh` on Linux/macOS, `toggle-cleanup.ps1` on Windows).
Log: `~/.opencode/toggle-cleanup.log`.

**Alternative — disable the official autoupdate**

If you prefer that the official installer never touches your binary (which makes
the guard unnecessary, though it doesn't get in the way either), disable
autoupdate in `opencode.json`:

```json
{
  "autoupdate": false
}
```

To update then, just run the install command again: it will download the latest
toggle build from the newest versioned release.

---

## 🔒 Security

- **🔐 SHA256 verified**: every release publishes `SHA256SUMS`; the installer
  checks the binary before installing it and aborts if it doesn't match.
- **🏭 Built in GitHub Actions**: binaries are produced in CI from the upstream
  code + patches, no hand-built binaries are uploaded.
- **🔗 Actions pinned to SHA**: fixed, specific versions of `actions/checkout`
  and `setup-bun`.
- **🔑 No secrets**: the workflow only uses `GITHUB_TOKEN` with minimal
  permissions.
- You can verify any binary with:
  `shasum -a 256 opencode` (macOS) or `sha256sum opencode` (Linux).

---

## 🆘 Problems?

Open an [issue](https://github.com/BenReynor/opencode-skill-toggle/issues) and
include your operating system and the version you are using. Thanks for
reporting! 🙌