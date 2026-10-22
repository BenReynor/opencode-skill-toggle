# ✨ opencode-skill-toggle

![CI](https://github.com/BenReynor/opencode-skill-toggle/actions/workflows/build-and-release.yml/badge.svg)
![Release](https://img.shields.io/github/v/release/BenReynor/opencode-skill-toggle)
![Platforms](https://img.shields.io/badge/platforms-Linux%20·%20macOS%20·%20Windows-informational)

> 🎚️ **opencode with a toggle for every skill.** Enable or disable each skill
> independently **per session**, and each session remembers its own choice
> between restarts.

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
| 🧠 | Each session **remembers its own choices** across restarts |
| 🆕 | New sessions start clean: only the built-in skill is on |
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

1. Go to [Releases](https://github.com/BenReynor/opencode-skill-toggle/releases)
   and download your binary:

   | System | File |
   |---------|---------|
   | 🐧 Linux x64 | `opencode-linux-x64` |
   | 🐧 Linux ARM | `opencode-linux-arm64` |
   | 🐧 Linux musl | `opencode-linux-*-musl` |
   | 🐧 Old Linux CPUs | `opencode-linux-x64-baseline` |
   | 🍎 macOS Intel | `opencode-darwin-x64` |
   | 🍎 macOS Apple Silicon | `opencode-darwin-arm64` |
   | 🪟 Windows x64 | `opencode-windows-x64` |

2. Put it where opencode lives (keep a copy of the previous one if you want to
   be able to roll back):
   - **Linux/macOS**: `~/.opencode/bin/opencode` (`chmod +x` it).
   - **Windows**: `%USERPROFILE%\.opencode\bin\opencode.exe`.
3. Verify it against `SHA256SUMS` from the same release.
4. Optional but recommended: run `./install.sh` (Linux/macOS) or `install.ps1`
   (Windows) **from the repository** to install the 🛡️ guard and the cleanup
   script. With `TOGGLE_USE_LOCAL=1 ./install.sh` it uses a binary you built
   locally (`./build.sh`) instead of downloading one.

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

The change applies to the **current session** and is saved to disk instantly;
that session keeps it across restarts. 🔁 A **new session starts with only the
built-in skill enabled**, so disabled skills do not clutter every conversation.
Sessions created before this version keep the global configuration they had.

The built-in `customize-opencode` skill is always available and cannot be
disabled. The state lives in `~/.local/share/opencode/skills-toggle.json`
(`%LOCALAPPDATA%\opencode\skills-toggle.json` on Windows).

### 🔌 Query the state via the API (advanced)

If you run `opencode serve`, the toggle is also reachable over HTTP, handy for
scripts and CI:

| Endpoint | Method | Effect |
|----------|--------|--------|
| `/skill` | GET | Skills enabled **for that session** |
| `/skill/status` | GET | State of each skill (enabled/disabled) |
| `/skill/:name/enable` | POST | Enables the skill in that session |
| `/skill/:name/disable` | POST | Disables it in that session |

All four accept `?session=<session-id>`. **Without `session`** they operate on
the template used for **new** sessions (by default only the built-in skill), so
scripts can preconfigure what new conversations start with.

The `/skill-toggle` dialog does exactly the same thing for the open session.

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

- **Do I have to enable skills in every new session?**
  New sessions start with only the built-in skill, so yes: enable the ones you
  need for that conversation. If you want a different starting point, call
  `/skill/<name>/enable` **without** `?session=` (advanced; that changes the
  template for future sessions, not the current one). Sessions created before
  the upgrade keep the old global configuration.

- **Does the guard also work on macOS / Windows?**
  Yes. macOS uses a LaunchAgent (launchd, every 15 min) and Windows a Scheduled
  Task (every 15 min and at logon); `install.sh` / `install.ps1` set them up
  automatically.

---

## 🔄 Updates

This repository self-rebuilds: whenever opencode releases a new version, it is
rebuilt with the toggle and published to a versioned release. That way you always
get the latest version **with** the toggle. It also rebuilds when the **patches**
change: every release carries a `PATCH_SHA256` asset, so a stale binary is never
served just because the upstream version number did not move.

> Each build is published to a **unique tag** (`toggle-<version>` or
> `toggle-<version>-r<build>`): the content of every release never changes, so the
> installers and the guard always download the correct binary with no risk of
> mixing old/new copies in GitHub's cache (they resolve the most recent `toggle-*`
> tag through the GitHub API).

The official update replaces `~/.opencode/bin/opencode` (or `opencode.exe`) with
the clean binary. To make sure the toggle is never lost, the installer leaves the
**auto-updating anti-overwrite guard enabled by default**:

### 🛡️ Anti-overwrite guard (already set up)

It keeps the toggle up to date automatically, without touching your data:

- After installing it leaves a **marker** with the SHA-256 of the toggle binary
  (an `opencode.sha256` next to the binary). Without that marker the guard
  **never** touches an unknown binary.
- **Restore** — if the binary was replaced (official autoupdate, `opencode upgrade`
  or any other means), the guard downloads the newest `toggle-*` build,
  **verifies its SHA256** against `SHA256SUMS`, makes a backup, replaces it
  atomically (without interrupting what is running) and only updates the marker if
  the new binary actually runs.
- **Proactive update** — if a newer `toggle-*` build was published, the guard
  detects it by comparing your binary's hash against the hashes in the newest
  release and updates it automatically. The version check is cached (1 hour by
  default) to avoid exhausting the API rate limit.
- What triggers it on each system:

  | System | Mechanism |
  |---------|-----------|
  | Linux | systemd `--user`: `.path` (inotify) + `.timer` every 15 min |
  | macOS | launchd LaunchAgent every 15 min |
  | Windows | Task Scheduler every 15 min and at logon |

> **No process stays waiting**: there is no daemon of its own. The system
> scheduler (already resident) does the watching and only runs the guard briefly
> when there is something to do. If you're offline, it just skips the check.

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

Force an immediate check/update right now:

```bash
# Linux / macOS
bash ~/.opencode/toggle-guard.sh --update

# Windows (PowerShell)
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.opencode\toggle-guard.ps1" -Update
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

### 🗑️ Uninstall

1. Remove the scheduler entry, if you installed the guard:

   ```bash
   # Linux
   systemctl --user disable --now opencode-toggle-guard.path opencode-toggle-guard.timer

   # macOS
   launchctl unload -w ~/Library/LaunchAgents/com.opencode.skill-toggle-guard.plist

   # Windows (PowerShell)
   Unregister-ScheduledTask -TaskName 'opencode-skill-toggle-guard' -Confirm:$false
   ```

2. Delete the installed helper scripts and (optionally) the state:

   ```bash
   rm -f ~/.opencode/toggle-guard.sh ~/.opencode/toggle-cleanup.sh
   rm -f ~/.opencode/bin/opencode.sha256
   rm -f ~/.local/share/opencode/skills-toggle.json
   ```

3. Replace `~/.opencode/bin/opencode` with the official binary using your usual
   method (official installer or `opencode upgrade`). The `.bak` next to it, if
   present, is the copy saved by the installer.

## 🔒 Security

- **🔐 SHA256 verified**: every release publishes `SHA256SUMS`; the installer
  checks the binary before installing it and aborts if it doesn't match. The
  guard and cleanup scripts are checked against `SHA256SUMS.scripts` and
  discarded on mismatch (older releases without that file are reported).
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
