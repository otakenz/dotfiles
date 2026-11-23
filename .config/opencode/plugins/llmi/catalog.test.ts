import { describe, expect, test } from "bun:test"
import { connectionKey, runtimePackage, toInventory } from "./catalog.ts"

describe("connectionKey", () => {
  test("distinguishes stored credentials by id and env connections by name", () => {
    expect(connectionKey({ type: "credential", id: "cred_a", label: "x", method: "key" })).toBe("credential:cred_a")
    expect(connectionKey({ type: "env", name: "LLMI_KEY" })).toBe("env:LLMI_KEY")
    expect(connectionKey({ type: "credential", id: "cred_a", label: "renamed", method: "key" })).toBe(
      connectionKey({ type: "credential", id: "cred_a", label: "x", method: "key" }),
    )
  })
})

const models = {
  data: [
    { id: "claude-4-8-opus-v1:0", created: 1677610602, mode: "chat" },
    { id: "gpt-5.6-sol", mode: "chat", max_input_tokens: 922000, max_output_tokens: 128000 },
    { id: "Qwen3-Embedding-8B", mode: "embedding" },
    { id: "old-blocked", mode: "chat" },
    { id: "DeepSeek-V4-Pro", mode: "chat" },
  ],
}

const info = {
  data: [
    {
      model_name: "claude-4-8-opus-v1:0",
      model_info: {
        mode: "chat",
        max_input_tokens: 1000000,
        max_output_tokens: 128000,
        supports_function_calling: true,
        supports_vision: true,
        input_cost_per_token: 0.000005,
        output_cost_per_token: 0.000025,
        cache_read_input_token_cost: 0.0000005,
        cache_creation_input_token_cost: 0.00000625,
      },
      litellm_params: { api_base: "https://must-not-be-published.internal" },
    },
    {
      model_name: "old-blocked",
      model_info: { mode: "chat", blocked: true },
    },
    {
      model_name: "DeepSeek-V4-Pro",
      model_info: {
        mode: "chat",
        max_input_tokens: 1000000,
        max_output_tokens: 384000,
        input_cost_per_token: 0.00000174,
        output_cost_per_token: 0.00000348,
        cache_read_input_token_cost: 1.45e-7,
      },
    },
  ],
}

describe("toInventory", () => {
  test("keeps only accessible chat models", () => {
    const inventory = toInventory(models, info)
    expect(inventory.map((model) => model.id)).toEqual([
      "claude-4-8-opus-v1:0",
      "gpt-5.6-sol",
      "DeepSeek-V4-Pro",
    ])
  })

  test("uses native protocol packages while preserving gateway model ids", () => {
    const [claude, gpt, deepseek] = toInventory(models, info)
    expect(claude).toMatchObject({
      id: "claude-4-8-opus-v1:0",
      modelID: "claude-4-8-opus-v1:0",
      package: "@opencode/ai/providers/anthropic-compatible",
      enabled: true,
    })
    expect(gpt.package).toBe("@opencode/ai/providers/openai-compatible/responses")
    expect(deepseek.package).toBeUndefined()
  })

  test("asks Chat Completions models to send prompt_cache_key so the gateway routes turns to a warm cache", () => {
    const [claude, gpt, deepseek] = toInventory(models, info)
    expect(deepseek.compatibility).toEqual({ supportsPromptCacheKey: true })
    expect(claude.compatibility).not.toHaveProperty("supportsPromptCacheKey")
    expect(gpt.compatibility).toBeUndefined()
  })

  test("keeps thinking.block_binding off Claude requests, which Azure behind the gateway rejects", () => {
    const [claude, gpt, deepseek] = toInventory(models, info)
    expect(claude.compatibility).toEqual({ supportsThinkingBlockBinding: false })
    expect(gpt.compatibility).toBeUndefined()
    expect(deepseek.compatibility).not.toHaveProperty("supportsThinkingBlockBinding")
  })

  test("converts per-token LiteLLM prices to per-million OpenCode costs", () => {
    const [claude] = toInventory(models, info)
    expect(claude.cost).toEqual([
      {
        input: 5,
        output: 25,
        cache: { read: 0.5, write: 6.25 },
      },
    ])
    expect(claude.limit).toEqual({ context: 1000000, input: 1000000, output: 128000 })
    expect(claude.capabilities).toMatchObject({ tools: true, input: ["text", "image"], output: ["text"] })
  })

  test("rounds away floating-point noise in per-million prices", () => {
    const [model] = toInventory(
      { data: [{ id: "gpt-6.1-sol", mode: "chat" }] },
      { data: [{ model_name: "gpt-6.1-sol", model_info: { mode: "chat", input_cost_per_token: 0.000002, output_cost_per_token: 0.00001, cache_read_input_token_cost: 1e-7 } }] },
    )
    expect(model.cost[0].cache.read).toBe(0.1)
  })

  test("falls back to limits from /models and zero cache prices", () => {
    const gpt = toInventory(models, info).find((model) => model.id === "gpt-5.6-sol")!
    expect(gpt.limit).toEqual({ context: 922000, input: 922000, output: 128000 })
    expect(gpt.cost).toEqual([])
  })

  test("never publishes upstream hosts, team ids or other LiteLLM internals", () => {
    const serialized = JSON.stringify(toInventory(models, info))
    expect(serialized).not.toContain("api_base")
    expect(serialized).not.toContain("litellm_params")
    expect(serialized).not.toContain("must-not-be-published.internal")
  })
})

describe("runtimePackage", () => {
  test("recognizes Claude ids behind provider prefixes", () => {
    expect(runtimePackage("vertex_ai/claude-opus-5")).toBe("@opencode/ai/providers/anthropic-compatible")
  })

  test("leaves non-GPT, non-Claude models on the provider default", () => {
    expect(runtimePackage("DeepSeek-V4-Pro")).toBeUndefined()
    expect(runtimePackage("Kimi-K2.6")).toBeUndefined()
  })
})
