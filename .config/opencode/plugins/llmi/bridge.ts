import { createServer, type Server } from "node:http"
import { timingSafeEqual } from "node:crypto"

type JsonObject = Record<string, unknown>

function pick(source: JsonObject, fields: string[]): JsonObject {
  return Object.fromEntries(fields.filter((field) => field in source).map((field) => [field, source[field]]))
}

/** Keep quota responses deliberately small: account/key metadata does not belong on the bridge. */
export function sanitizeBudget(body: JsonObject): JsonObject {
  return pick(body, ["spend", "max_budget", "pct_used"])
}

export function sanitizeCostSummary(body: JsonObject): JsonObject {
  return pick(body, ["from", "to", "input_tokens", "output_tokens", "cost_usd", "request_count", "currency"])
}

export function combineQuota(budget: JsonObject, cost: JsonObject): JsonObject {
  return {
    ...sanitizeBudget(budget),
    cost_usd_7d: cost.cost_usd,
    requests_7d: cost.request_count,
  }
}

export interface BridgeOptions {
  baseURL: string
  userID: string
  /** Bridge-only secret. Never the gateway key: whoever owns the port receives it. */
  token: string
  getAuthorization: () => Promise<string | undefined>
  cacheMs?: number
}

async function fetchObject(url: string, authorization: string | undefined): Promise<JsonObject> {
  const result = await fetch(url, {
    headers: authorization ? { Authorization: authorization } : {},
    // Stay under opencode-quota's 5 s requestTimeoutMs so it gets a 502, not a timeout.
    signal: AbortSignal.timeout(4_000),
  })
  const body = await result.json()
  if (!result.ok || !body || typeof body !== "object" || Array.isArray(body)) throw new Error(`LLMi ${result.status}`)
  return body as JsonObject
}

export function tokenMatches(header: string | undefined, token: string): boolean {
  if (!token) return false
  const given = Buffer.from(header ?? "")
  const expected = Buffer.from(`Bearer ${token}`)
  return given.length === expected.length && timingSafeEqual(given, expected)
}

/**
 * Local-only adapter for opencode-quota: it allows one definition per provider and rejects URLs
 * with query strings, while LLMi needs `?user_id=` and two endpoints.
 */
export function startBridge(port: number, options: BridgeOptions): Server {
  const cacheMs = options.cacheMs ?? 60_000
  let cached: { at: number; body: Promise<JsonObject> } | undefined

  const quota = () => {
    if (cached && Date.now() - cached.at < cacheMs) return cached.body
    const body = (async () => {
      const authorization = await options.getAuthorization()
      const [budget, cost] = await Promise.all([
        fetchObject(`${options.baseURL}/v1/budget/status?user_id=${encodeURIComponent(options.userID)}`, authorization),
        fetchObject(`${options.baseURL}/v1/cost/summary`, authorization),
      ])
      return combineQuota(budget, cost)
    })()
    cached = { at: Date.now(), body }
    body.catch(() => {
      if (cached?.body === body) cached = undefined
    })
    return body
  }

  const server = createServer(async (request, response) => {
    const host = request.headers.host ?? ""
    const { port: own } = server.address() as { port: number }
    if (host !== `127.0.0.1:${own}` && host !== `localhost:${own}`) {
      response.writeHead(403).end()
      return
    }
    if (!tokenMatches(request.headers.authorization, options.token)) {
      response.writeHead(401).end()
      return
    }
    if (request.method !== "GET" || request.url !== "/quota") {
      response.writeHead(404).end()
      return
    }
    try {
      const body = await quota()
      response.writeHead(200, { "content-type": "application/json" })
      response.end(JSON.stringify(body))
    } catch {
      response.writeHead(502, { "content-type": "application/json" })
      response.end(JSON.stringify({ error: "LLMi quota unavailable" }))
    }
  })
  return server.listen(port, "127.0.0.1")
}
