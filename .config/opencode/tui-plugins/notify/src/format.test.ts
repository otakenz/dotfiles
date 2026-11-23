import { describe, expect, test } from "bun:test"
import { clean, client, sequence, shown } from "./format.ts"

describe("clean", () => {
  test("replaces separators and drops control characters", () =>
    expect(clean("a;b\nc\x1bd", 200)).toBe("a b cd"))
  test("cuts to the maximum length", () => expect(clean("x".repeat(300), 200).length).toBe(200))
  test("empty for undefined", () => expect(clean(undefined, 200)).toBe(""))
})

describe("sequence", () => {
  test("OSC 777 notify", () => expect(sequence("T", "B")).toBe("\x1b]777;notify;T;B\x1b\\"))
})

describe("client", () => {
  test("most recently active", () => expect(client("100 /dev/pts/1\n300 /dev/pts/2\n200 /dev/pts/3\n")).toBe("/dev/pts/2"))
  test("none attached", () => expect(client("")).toBeUndefined())
})

describe("shown", () => {
  test("open tab", () => expect(shown("a", ["b", "a"], undefined)).toBe(true))
  test("session of another TUI", () => expect(shown("c", ["b", "a"], "c")).toBe(false))
  test("without tabs: current route", () => expect(shown("a", undefined, "a")).toBe(true))
  test("without tabs: other route", () => expect(shown("a", undefined, undefined)).toBe(false))
})
