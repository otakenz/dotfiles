import { describe, expect, test } from "bun:test"
import { bar, pollDelay, pushLevel, render, type Status } from "./format.ts"

const idle: Status = { state: "idle", level_dbfs: null, elapsed_s: null, warning: null, warning_age_s: null }
const recording: Status = { ...idle, state: "recording", level_dbfs: -30, elapsed_s: 4.24 }

describe("render", () => {
  test("off when unreachable", () => expect(render(null, [])).toBe("🎙 off"))
  test("ready when idle", () => expect(render(idle, [])).toBe("🎙 ready"))
  test("recording shows bar and time", () =>
    expect(render(recording, [-60, 0])).toBe("🔴 ▁▁▁▁▁▁█ 4.2s"))
  test("capture stopped", () =>
    expect(render({ ...idle, state: "stopped" }, [])).toBe("⏹ recording stopped – release Ctrl+Q"))
  test("transcribing", () => expect(render({ ...idle, state: "transcribing" }, [])).toBe("… transcribing"))
  test("recent warning", () =>
    expect(render({ ...idle, warning: "no audio – check mic", warning_age_s: 3 }, [])).toBe("⚠ no audio – check mic"))
  test("old warning falls back to ready", () =>
    expect(render({ ...idle, warning: "no speech", warning_age_s: 10 }, [])).toBe("🎙 ready"))
})

describe("bar", () => {
  test("maps -60..0 dBFS and pads to 7", () => expect(bar([-60, -30, 0])).toBe("▁▁▁▁▁▅█"))
  test("clamps out of range", () => expect(bar([-120, 6])).toBe("▁▁▁▁▁▁█"))
  test("keeps only the last 7", () => expect(bar([0, 0, 0, 0, 0, 0, 0, -60])).toBe("██████▁"))
})

describe("pushLevel", () => {
  test("appends while recording, caps at 7", () => {
    let h: number[] = []
    for (let i = 0; i < 9; i++) h = pushLevel(h, recording, "recording")
    expect(h).toHaveLength(7)
  })
  test("resets when a recording starts", () => expect(pushLevel([-10, -10], recording, "idle")).toEqual([-30]))
  test("unchanged when not recording", () => expect(pushLevel([-10], idle, "idle")).toEqual([-10]))
})

describe("pollDelay", () => {
  test("fast while busy", () => {
    expect(pollDelay(recording)).toBe(200)
    expect(pollDelay({ ...idle, state: "transcribing" })).toBe(200)
    expect(pollDelay({ ...idle, state: "stopped" })).toBe(200)
  })
  test("slow otherwise", () => {
    expect(pollDelay(idle)).toBe(2000)
    expect(pollDelay(null)).toBe(2000)
  })
})
