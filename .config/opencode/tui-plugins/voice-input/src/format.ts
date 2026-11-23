export type Status = {
  state: "idle" | "recording" | "stopped" | "transcribing"
  level_dbfs: number | null
  elapsed_s: number | null
  warning: string | null
  warning_age_s: number | null
}

const BLOCKS = "▁▂▃▄▅▆▇█"
const WIDTH = 7
const WARNING_S = 10

export function bar(levels: number[]): string {
  const cells = levels.slice(-WIDTH).map((db) => {
    const i = Math.round(((Math.min(0, Math.max(-60, db)) + 60) / 60) * (BLOCKS.length - 1))
    return BLOCKS[i]
  })
  return BLOCKS[0].repeat(WIDTH - cells.length) + cells.join("")
}

export function pushLevel(history: number[], status: Status | null, prev: Status["state"] | null): number[] {
  if (status?.state !== "recording" || status.level_dbfs === null) return history
  const base = prev === "recording" ? history : []
  return [...base, status.level_dbfs].slice(-WIDTH)
}

export function render(status: Status | null, history: number[], seen: boolean): string {
  if (status === null) return seen ? "🎙 off" : ""
  if (status.state === "recording") return `🔴 ${bar(history)} ${(status.elapsed_s ?? 0).toFixed(1)}s`
  if (status.state === "stopped") return "⏹ recording stopped – release Ctrl+Q"
  if (status.state === "transcribing") return "… transcribing"
  if (status.warning && status.warning_age_s !== null && status.warning_age_s < WARNING_S) return `⚠ ${status.warning}`
  return "🎙 ready"
}

export function pollDelay(status: Status | null): number {
  return status === null || status.state === "idle" ? 2000 : 200
}
