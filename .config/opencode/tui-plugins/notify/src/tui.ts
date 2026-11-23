import { execFile } from "node:child_process"
import { open } from "node:fs/promises"
import { promisify } from "node:util"
import { Plugin } from "@opencode/plugin/tui"
import { clean, client, sequence, shown } from "./format.ts"

const run = promisify(execFile)

// Inside tmux, write to the outer terminal (WezTerm) of a client attached to this pane's session:
// tmux passes notifications only from the visible pane, and only DCS-wrapped.
// Outside tmux, /dev/tty: the renderer owns stdout.
async function terminal(): Promise<string | undefined> {
  if (!process.env.TMUX) return "/dev/tty"
  const target = process.env.TMUX_PANE ? ["-t", process.env.TMUX_PANE] : []
  const { stdout } = await run("tmux", ["list-clients", ...target, "-F", "#{client_activity} #{client_tty}"], { timeout: 1000 })
  return client(stdout)
}

async function notify(body: string) {
  const path = await terminal()
  if (!path) return
  const tty = await open(path, "a")
  try {
    await tty.write(sequence("OpenCode: session done", body))
  } finally {
    await tty.close()
  }
}

export default Plugin.define({
  id: "notify.session-done",
  setup(context) {
    const sessions = context.data.session
    const childRunning = (id: string) =>
      sessions.family(id).some((other) => other !== id && sessions.get(other)?.parentID === id && sessions.status(other) === "running")
    const visible = (id: string) => {
      const tabs = context.ui.tabs.enabled() ? context.ui.tabs.list().map((tab) => tab.sessionID) : undefined
      const route = context.ui.router.current()
      return shown(id, tabs, route.type === "session" ? route.sessionID : undefined)
    }

    return context.data.on("session.execution.succeeded", (event) => {
      try {
        const id = event.data.sessionID
        const session = sessions.get(id)
        if (!session || session.parentID || childRunning(id) || !visible(id)) return
        notify(clean(session.title, 200) || "OpenCode").catch(() => {})
      } catch {}
    })
  },
})
