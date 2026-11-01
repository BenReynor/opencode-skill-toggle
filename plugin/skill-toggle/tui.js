// skill-toggle for opencode 2.x: a TUI plugin.
//
// opencode 2.x already filters skills through permissions. When a session has
// a rule { action: "skill", resource: <id>, effect: "deny" }, that skill is left
// out of the list the model sees and the `skill` tool refuses to load it.
// Session rules are evaluated after the agent's, so they win. This plugin only
// adds and removes those deny rules for the open session. It needs no patched
// binary, so opencode can update itself normally.
//
// Install: copy this directory to ~/.config/opencode/plugins/skill-toggle/
// (or <project>/.opencode/plugins/skill-toggle/) and restart opencode.
//
// Plain JavaScript with no imports on purpose, so it needs no build step and no
// dependencies.
//
// Auto-update: at most every 12 hours the plugin compares itself with the copy
// published in the repository's "latest" release (skill-toggle-tui.js, checked
// against SHA256SUMS.scripts). When they differ it replaces this file, and
// opencode hot-reloads it. Only the global install is updated. Turn it off
// with SKILL_TOGGLE_AUTOUPDATE=0 or the plugin option { "autoUpdate": false }.

const ACTION = "skill"
const RELEASE =
  process.env.SKILL_TOGGLE_RELEASE_URL || "https://github.com/BenReynor/opencode-skill-toggle/releases/download/latest"
const ASSET = "skill-toggle-tui.js"
const CHECK_EVERY_MS = 12 * 60 * 60 * 1000

// Returns true when a new version was installed.
export async function selfUpdate() {
  const [fs, path, os, crypto] = await Promise.all([
    import("node:fs/promises"),
    import("node:path"),
    import("node:os"),
    import("node:crypto"),
  ])
  const home = os.homedir()
  const config = process.env.XDG_CONFIG_HOME || path.join(home, ".config")
  const self = path.join(config, "opencode", "plugins", "skill-toggle", "tui.js")
  const stampDir = path.join(process.env.XDG_CACHE_HOME || path.join(home, ".cache"), "opencode-skill-toggle")
  const stamp = path.join(stampDir, "last-check")

  const current = await fs.readFile(self).catch(() => undefined)
  if (!current) return false // not the global install (e.g. a project copy): leave it alone
  const last = await fs.stat(stamp).then((info) => info.mtimeMs, () => 0)
  if (Date.now() - last < CHECK_EVERY_MS) return false
  await fs.mkdir(stampDir, { recursive: true })
  await fs.writeFile(stamp, new Date().toISOString())

  const get = async (name) => {
    const response = await fetch(`${RELEASE}/${name}`, { redirect: "follow", signal: AbortSignal.timeout(15000) })
    if (!response.ok) throw new Error(`${name}: HTTP ${response.status}`)
    return Buffer.from(await response.arrayBuffer())
  }
  const sha = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex")

  const sums = (await get("SHA256SUMS.scripts")).toString("utf8")
  const line = sums.split("\n").find((entry) => entry.trim().split(/\s+/)[1]?.replace(/^\.\//, "") === ASSET)
  const expected = line?.trim().split(/\s+/)[0]?.toLowerCase()
  if (!expected || expected === sha(current)) return false

  const next = await get(ASSET)
  if (sha(next) !== expected) throw new Error("checksum mismatch, update discarded")
  const tmp = `${self}.${process.pid}.tmp`
  await fs.writeFile(tmp, next)
  await fs.rename(tmp, self) // atomic; opencode notices the change and reloads the plugin
  return true
}

const shorten = (text, max = 48) => {
  if (!text) return undefined
  const flat = text.replace(/\s+/g, " ").trim()
  return flat.length > max ? flat.slice(0, max - 1).trimEnd() + "…" : flat
}

const isDeny = (rule, id) => rule.action === ACTION && rule.resource === id && rule.effect === "deny"

export default {
  id: "skill-toggle",
  setup(ctx) {
    const toast = (message, variant = "info") => ctx.ui.toast.show({ title: "Skills", message, variant })

    let timer
    if (process.env.SKILL_TOGGLE_AUTOUPDATE !== "0" && ctx.options.autoUpdate !== false) {
      // Never block startup, and never fail loudly: offline just means "later".
      timer = setTimeout(() => {
        selfUpdate().then(
          (updated) => updated && toast("skill-toggle was updated to the newest version", "success"),
          () => {},
        )
      }, 5000)
    }

    const currentSessionID = () => {
      const route = ctx.ui.router.current()
      return route && route.type === "session" ? route.sessionID : undefined
    }

    const loadSkills = async () => {
      let list = ctx.data.location.skill.list()
      if (!list) {
        await ctx.data.location.skill.sync()
        list = ctx.data.location.skill.list() ?? []
      }
      return [...list].sort((a, b) => a.name.localeCompare(b.name))
    }

    const loadPermissions = async (sessionID) => {
      const cached = ctx.data.session.get(sessionID)
      if (cached) return [...(cached.permissions ?? [])]
      const info = await ctx.client.session.get({ sessionID })
      return [...(info?.permissions ?? [])]
    }

    // setPermissions replaces the whole ruleset: keep every rule that is not
    // one of our skill denies (saved "always allow" answers, other tools...).
    const save = (sessionID, permissions) => ctx.client.session.update({ sessionID, permissions })

    const setEnabled = (permissions, id, enabled) => {
      const kept = permissions.filter((rule) => !isDeny(rule, id))
      return enabled ? kept : [...kept, { action: ACTION, resource: id, effect: "deny" }]
    }

    const open = async (sessionID, permissions, current) => {
      let skills
      try {
        skills = await loadSkills()
      } catch (error) {
        toast(`Could not load skills: ${error instanceof Error ? error.message : String(error)}`, "error")
        return
      }
      if (skills.length === 0) {
        toast("No skills are installed")
        return
      }
      const disabled = new Set(permissions.filter((rule) => isDeny(rule, rule.resource)).map((rule) => rule.resource))
      const enabledCount = skills.filter((skill) => !disabled.has(skill.id)).length

      const apply = async (next, focus, message) => {
        try {
          await save(sessionID, next)
        } catch (error) {
          toast(`Could not save: ${error instanceof Error ? error.message : String(error)}`, "error")
          return
        }
        if (message) toast(message, "success")
        await open(sessionID, next, focus)
      }

      const toggle = (id) => {
        if (id === undefined) return
        const enable = disabled.has(id)
        return apply(setEnabled(permissions, id, enable), id)
      }

      const setAll = (enabled) => {
        let next = permissions
        for (const skill of skills) next = setEnabled(next, skill.id, enabled)
        return apply(next, current, enabled ? "All skills enabled" : "All skills disabled")
      }

      const pending = ctx.ui.dialog.select({
        title: `Skills (${enabledCount}/${skills.length} enabled in this session)`,
        placeholder: "Search",
        current,
        options: skills.map((skill) => ({
          title: skill.name,
          value: skill.id,
          description: shorten(skill.description),
          footer: disabled.has(skill.id) ? "○ Disabled" : "✓ Enabled",
        })),
        actions: [
          { bind: "space", title: "toggle", onTrigger: (id) => void toggle(id) },
          { bind: "ctrl+e", title: "enable all", selection: "none", onTrigger: () => void setAll(true) },
          { bind: "ctrl+d", title: "disable all", selection: "none", onTrigger: () => void setAll(false) },
        ],
      })
      ctx.ui.dialog.set({ size: "large" })
      const choice = await pending
      // Enter toggles too; Esc resolves undefined and closes.
      if (choice !== undefined) await toggle(choice)
    }

    ctx.keymap.layer(() => ({
      mode: "global",
      commands: [
        {
          id: "skill-toggle.open",
          title: "Toggle Skills",
          description: "Enable or disable each skill for this session",
          group: "Session",
          palette: true,
          slash: { name: "skill-toggle" },
          run: async () => {
            const sessionID = currentSessionID()
            if (!sessionID) {
              toast("Open or start a session first: skills are toggled per session", "warning")
              return
            }
            let permissions
            try {
              permissions = await loadPermissions(sessionID)
            } catch (error) {
              toast(`Could not read the session: ${error instanceof Error ? error.message : String(error)}`, "error")
              return
            }
            await open(sessionID, permissions)
          },
        },
      ],
    }))

    return () => clearTimeout(timer)
  },
}
