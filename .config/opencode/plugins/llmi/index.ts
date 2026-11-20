import { Model, Plugin, Provider } from "@opencode/plugin"
import type { ConnectionInfo as Connection } from "@opencode/client"
import type { Server } from "node:http"
import { connectionKey, toInventory, type DiscoveredModel } from "./catalog.ts"
import { startBridge } from "./bridge.ts"

const providerID = Provider.ID.make("aumovio-llmi")
const baseURL = "https://llm-gateway.ve42034x.automotive-wan.com:443"
const TOKEN_ENV = "LLMI_QUOTA_TOKEN"

/** One bridge per server process, shared by every location that enables it. */
type SharedBridge = { server: Server; refs: number; getters: Set<() => Promise<string | undefined>> }
const shared = globalThis as typeof globalThis & { __llmiBridge?: SharedBridge }

function acquireBridge(port: number, userID: string, token: string, getter: () => Promise<string | undefined>) {
  let bridge = shared.__llmiBridge
  if (!bridge) {
    const getters = new Set<() => Promise<string | undefined>>()
    const server = startBridge(port, {
      baseURL,
      userID,
      token,
      getAuthorization: async () => {
        for (const get of getters) {
          const value = await get().catch(() => undefined)
          if (value) return value
        }
        return undefined
      },
    })
    server.on("listening", () => console.log(`[llmi] quota bridge listening on 127.0.0.1:${port}`))
    server.on("error", (error) => console.error(`[llmi] quota bridge failed on ${port}: ${error.message}`))
    bridge = shared.__llmiBridge = { server, refs: 0, getters }
  }
  bridge.refs++
  bridge.getters.add(getter)
  return () => {
    const current = shared.__llmiBridge
    if (!current) return
    current.getters.delete(getter)
    if (--current.refs <= 0) {
      current.server.close()
      shared.__llmiBridge = undefined
    }
  }
}

export default Plugin.define({
  id: "llmi",
  async setup(ctx) {
    if (ctx.options.enabled !== true) return

    const source: Provider.Info = {
      ...Provider.Info.empty(providerID),
      name: "AUMOVIO LLMi",
      activation: "enabled",
      package: "@opencode/ai/providers/openai-compatible",
      settings: { baseURL: `${baseURL}/v1` },
      headers: { "X-Application-Name": "opencode" },
    }
    let published: { models: DiscoveredModel[]; connection: Connection } | undefined
    let generation = 0

    const credential = async (connection: Connection) => {
      const value = await ctx.integration.connection.resolve(connection)
      return value?.type === "key" ? `Bearer ${value.key}` : undefined
    }
    const authorization = async () => {
      const connection = await ctx.integration.connection.active(providerID)
      return connection ? credential(connection) : undefined
    }

    await ctx.provider.transform((editor) => {
      if (!published) return
      editor.add({
        info: source,
        models: published.models.map((model) => ({ ...model, providerID })) as unknown as Model.Info[],
      })
    })

    const refresh = async () => {
      const current = ++generation
      try {
        const connection = await ctx.integration.connection.active(providerID)
        const auth = connection ? await credential(connection) : undefined
        if (!connection || !auth) {
          if (published) {
            published = undefined
            await ctx.provider.reload()
          }
          return
        }
        // sourceConnection hides plugin-defined providers in 2.3.2, so drop another
        // account's models here before fetching this one's.
        if (published && connectionKey(published.connection) !== connectionKey(connection)) {
          published = undefined
          await ctx.provider.reload()
        }
        const headers = { Authorization: auth, "X-Application-Name": "opencode" }
        const [modelsResponse, infoResponse] = await Promise.all([
          fetch(`${baseURL}/v1/models`, { headers, signal: AbortSignal.timeout(10_000) }),
          fetch(`${baseURL}/v1/model/info`, { headers, signal: AbortSignal.timeout(10_000) }),
        ])
        if (!modelsResponse.ok || !infoResponse.ok) {
          console.warn(`[llmi] catalog refresh failed: models=${modelsResponse.status} info=${infoResponse.status}`)
          return
        }
        const models = toInventory(await modelsResponse.json(), await infoResponse.json())
        if (current !== generation) return
        published = { models, connection }
        await ctx.provider.reload()
        console.log(`[llmi] published ${models.length} chat models with gateway pricing`)
      } catch (error) {
        console.warn(`[llmi] catalog refresh failed: ${String(error).slice(0, 160)}`)
      }
    }

    await refresh()
    const seconds = typeof ctx.options.refreshSeconds === "number" ? ctx.options.refreshSeconds : 900
    const timer = seconds > 0 ? setInterval(() => void refresh(), seconds * 1000) : undefined

    const events = new AbortController()
    void (async () => {
      for await (const event of ctx.event.subscribe({
        types: ["credential.updated", "credential.switched"],
        signal: events.signal,
      })) {
        if (event.data.integrationID === providerID) await refresh()
      }
    })().catch((error) => {
      if (!events.signal.aborted) console.warn(`[llmi] credential watch stopped: ${String(error).slice(0, 160)}`)
    })

    let releaseBridge: (() => void) | undefined
    if (ctx.options.bridge === true) {
      const port = typeof ctx.options.bridgePort === "number" ? ctx.options.bridgePort : 43117
      const userID = typeof ctx.options.bridgeUserID === "string" ? ctx.options.bridgeUserID : process.env.USER
      const token = process.env[TOKEN_ENV] ?? ""
      if (!userID) console.warn("[llmi] quota bridge requested but no bridgeUserID or USER is set")
      else {
        // Hold the port even without a token (then every request is rejected), so a
        // fallback key from opencode-quota can only ever reach this process.
        if (token.length < 32) console.warn(`[llmi] quota bridge rejects all requests: set ${TOKEN_ENV} (32+ chars)`)
        releaseBridge = acquireBridge(port, userID, token.length >= 32 ? token : "", authorization)
      }
    }

    return () => {
      if (timer) clearInterval(timer)
      events.abort()
      releaseBridge?.()
    }
  },
})
