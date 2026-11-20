import { Plugin } from "@opencode/plugin/tui"
import { createSignal } from "solid-js"
import { pollDelay, pushLevel, render, type Status } from "./format.ts"

const URL = "http://127.0.0.1:47821/status"

async function fetchStatus(): Promise<Status | null> {
  try {
    const response = await fetch(URL, {
      headers: { "X-Voice-Input": "1" },
      signal: AbortSignal.timeout(1000),
    })
    return response.ok ? ((await response.json()) as Status) : null
  } catch {
    return null
  }
}

export default Plugin.define({
  id: "voice-input.indicator",
  setup(context) {
    const [line, setLine] = createSignal(render(null, []))
    let history: number[] = []
    let prev: Status["state"] | null = null
    let timer: ReturnType<typeof setTimeout> | undefined
    let stopped = false

    const tick = async () => {
      const status = await fetchStatus()
      if (stopped) return
      history = pushLevel(history, status, prev)
      prev = status?.state ?? null
      setLine(render(status, history))
      timer = setTimeout(tick, pollDelay(status))
    }
    void tick()

    context.ui.slot({
      append: "prompt.footer.status",
      render: () => <text fg={context.theme.text.base}>{line()}</text>,
    })

    return () => {
      stopped = true
      clearTimeout(timer)
    }
  },
})
