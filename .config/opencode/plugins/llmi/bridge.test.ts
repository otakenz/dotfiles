import { afterEach, describe, expect, test } from "bun:test"
import { createServer, type Server } from "node:http"
import type { AddressInfo } from "node:net"
import { combineQuota, sanitizeBudget, sanitizeCostSummary, startBridge, tokenMatches } from "./bridge.ts"

describe("tokenMatches", () => {
  test("never matches when no token is configured", () => {
    expect(tokenMatches("Bearer ", "")).toBe(false)
    expect(tokenMatches(undefined, "")).toBe(false)
  })

  test("matches only the exact bearer token", () => {
    expect(tokenMatches("Bearer abc", "abc")).toBe(true)
    expect(tokenMatches("Bearer abd", "abc")).toBe(false)
    expect(tokenMatches("abc", "abc")).toBe(false)
  })
})

describe("quota bridge sanitization", () => {
  test("combines budget and 7-day spend into one flat quota object", () => {
    expect(
      combineQuota(
        { spend: 4.4, max_budget: 200, pct_used: 2.2, user_id: "x" },
        { key_prefix: "secret", cost_usd: 0.02, request_count: 12, currency: "USD" },
      ),
    ).toEqual({ spend: 4.4, max_budget: 200, pct_used: 2.2, cost_usd_7d: 0.02, requests_7d: 12 })
  })

  test("keeps only the three budget fields", () => {
    expect(
      sanitizeBudget({ spend: 4.438052, max_budget: 200, pct_used: 2.2, user_id: "someone", extra: true }),
    ).toEqual({ spend: 4.438052, max_budget: 200, pct_used: 2.2 })
  })

  test("drops the key prefix from cost summaries", () => {
    const result = sanitizeCostSummary({
      key_prefix: "secret-prefix",
      from: "2026-11-13T00:00:00Z",
      to: "2026-11-20T00:00:00Z",
      input_tokens: 26554,
      output_tokens: 12,
      cache_read_input_tokens: 0,
      cache_creation_input_tokens: 0,
      cost_usd: 0.0116996,
      request_count: 6,
      currency: "USD",
    })
    expect(result).toEqual({
      from: "2026-11-13T00:00:00Z",
      to: "2026-11-20T00:00:00Z",
      input_tokens: 26554,
      output_tokens: 12,
      cost_usd: 0.0116996,
      request_count: 6,
      currency: "USD",
    })
    expect(JSON.stringify(result)).not.toContain("secret-prefix")
  })
})

describe("quota bridge server", () => {
  const servers: Server[] = []
  afterEach(() => {
    servers.splice(0).forEach((server) => server.close())
  })

  async function listen(server: Server): Promise<number> {
    servers.push(server)
    if (!server.listening) await new Promise((resolve) => server.once("listening", resolve))
    return (server.address() as AddressInfo).port
  }

  async function setup() {
    const upstream = { calls: 0, authorization: [] as (string | undefined)[] }
    const gateway = createServer((request, response) => {
      upstream.calls++
      upstream.authorization.push(request.headers.authorization)
      response.writeHead(200, { "content-type": "application/json" })
      response.end(
        JSON.stringify(
          request.url?.startsWith("/v1/budget/status")
            ? { spend: 1, max_budget: 200, pct_used: 0.5 }
            : { cost_usd: 0.25, request_count: 3, key_prefix: "secret" },
        ),
      )
    }).listen(0, "127.0.0.1")
    const gatewayPort = await listen(gateway)
    const bridge = startBridge(0, {
      baseURL: `http://127.0.0.1:${gatewayPort}`,
      userID: "me",
      token: "bridge-token",
      getAuthorization: async () => "Bearer gateway-key",
    })
    const port = await listen(bridge)
    return { upstream, url: `http://127.0.0.1:${port}/quota` }
  }

  test("rejects every request when no bridge token is configured", async () => {
    const bridge = startBridge(0, {
      baseURL: "http://127.0.0.1:9",
      userID: "me",
      token: "",
      getAuthorization: async () => "Bearer gateway-key",
    })
    const port = await listen(bridge)
    const url = `http://127.0.0.1:${port}/quota`
    expect((await fetch(url, { headers: { Authorization: "Bearer " } })).status).toBe(401)
    expect((await fetch(url, { headers: { Authorization: "Bearer gateway-key" } })).status).toBe(401)
  })

  test("rejects requests without the bridge token", async () => {
    const { upstream, url } = await setup()
    expect((await fetch(url)).status).toBe(401)
    expect((await fetch(url, { headers: { Authorization: "Bearer gateway-key" } })).status).toBe(401)
    expect(upstream.calls).toBe(0)
  })

  test("rejects foreign Host headers (DNS rebinding)", async () => {
    const { upstream, url } = await setup()
    const { request } = await import("node:http")
    const status = await new Promise<number>((resolve, reject) => {
      const req = request(url, { headers: { Host: "evil.example", Authorization: "Bearer bridge-token" } }, (res) => {
        res.resume()
        resolve(res.statusCode ?? 0)
      })
      req.on("error", reject)
      req.end()
    })
    expect(status).toBe(403)
    expect(upstream.calls).toBe(0)
  })

  test("serves sanitized quota with the token and caches upstream calls", async () => {
    const { upstream, url } = await setup()
    const headers = { Authorization: "Bearer bridge-token" }
    const first = await (await fetch(url, { headers })).json()
    await fetch(url, { headers })
    expect(first).toEqual({ spend: 1, max_budget: 200, pct_used: 0.5, cost_usd_7d: 0.25, requests_7d: 3 })
    expect(upstream.calls).toBe(2)
    expect(upstream.authorization).toEqual(["Bearer gateway-key", "Bearer gateway-key"])
  })
})
