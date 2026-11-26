import { describe, expect, test } from "bun:test"
import { apiTypeFor, GROUP_NAME, mergeGroup, toBudget, toModels, validCatalogResponses } from "./catalog"

const BASE = "https://gw.test"

const models = {
  data: [
    { id: "claude-5-0-sonnet-v1:0" },
    { id: "vertex_ai/claude-opus-5" },
    { id: "gpt-5.6-terra" },
    { id: "DeepSeek-V4-Pro" },
    { id: "text-embedding-3" },
    { id: "no-tools" },
    { id: "blocked-one" },
  ],
}
const info = {
  data: [
    { model_name: "claude-5-0-sonnet-v1:0", model_info: { mode: "chat", max_input_tokens: 1_000_000, max_output_tokens: 128_000, supports_vision: true } },
    { model_name: "vertex_ai/claude-opus-5", model_info: { mode: "chat" } },
    { model_name: "gpt-5.6-terra", model_info: { mode: "chat", max_input_tokens: 922_000, max_output_tokens: 128_000 } },
    { model_name: "DeepSeek-V4-Pro", model_info: { mode: "chat", max_input_tokens: 300_000, max_output_tokens: 384_000 } },
    { model_name: "text-embedding-3", model_info: { mode: "embedding" } },
    { model_name: "no-tools", model_info: { mode: "chat", supports_function_calling: false } },
    { model_name: "blocked-one", model_info: { mode: "chat", blocked: true } },
  ],
}

describe("apiTypeFor", () => {
  test("Claude on Messages, GPT on Responses, rest on Chat Completions", () => {
    expect(apiTypeFor("claude-5-0-sonnet-v1:0")).toBe("messages")
    expect(apiTypeFor("vertex_ai/claude-opus-5")).toBe("messages")
    expect(apiTypeFor("gpt-5.6-sol")).toBe("responses")
    expect(apiTypeFor("o3-mini")).toBe("responses")
    expect(apiTypeFor("DeepSeek-V4-Pro")).toBe("chat-completions")
  })
})

describe("toModels", () => {
  const result = toModels(BASE, models, info)
  const byId = Object.fromEntries(result.map((m) => [m.id, m]))

  test("keeps only chat models that can call tools and are not blocked", () => {
    expect(result.map((m) => m.id).sort()).toEqual(
      ["DeepSeek-V4-Pro", "claude-5-0-sonnet-v1:0", "gpt-5.6-terra", "vertex_ai/claude-opus-5"].sort(),
    )
  })

  test("sets the full endpoint URL per API type", () => {
    expect(byId["claude-5-0-sonnet-v1:0"].url).toBe(`${BASE}/v1/messages`)
    expect(byId["gpt-5.6-terra"].url).toBe(`${BASE}/v1/responses`)
    expect(byId["DeepSeek-V4-Pro"].url).toBe(`${BASE}/v1/chat/completions`)
  })

  test("Responses models are stateless; others carry no statefulResponses", () => {
    expect(byId["gpt-5.6-terra"].statefulResponses).toBe(false)
    expect("statefulResponses" in byId["claude-5-0-sonnet-v1:0"]).toBe(false)
  })

  test("limits from model info, defaults when missing, output below context", () => {
    expect(byId["claude-5-0-sonnet-v1:0"]).toMatchObject({ contextWindow: 1_000_000, maxOutputTokens: 128_000, vision: true })
    expect(byId["vertex_ai/claude-opus-5"]).toMatchObject({ contextWindow: 200_000, maxOutputTokens: 32_000, vision: false })
    expect(byId["DeepSeek-V4-Pro"]).toMatchObject({ contextWindow: 300_000, maxOutputTokens: 150_000 })
  })

  test("never carries a credential", () => {
    expect(JSON.stringify(result)).not.toMatch(/apiKey|Authorization|x-api-key/i)
  })

  test("tolerates empty or malformed responses", () => {
    expect(toModels(BASE, {}, {})).toEqual([])
    expect(toModels(BASE, { data: [{ id: 1 }] }, { data: "x" })).toEqual([])
  })
})

describe("mergeGroup", () => {
  const catalog = toModels(BASE, models, info)
  const other = { name: "Other", vendor: "openai", apiKey: "${input:other}", models: [{ id: "x" }] }
  const group = { name: GROUP_NAME, vendor: "customendpoint", apiKey: "${input:llmi}", apiType: "responses", models: [{ id: "old" }] }

  test("replaces only the LLMi group's models and keeps its key reference", () => {
    const result = mergeGroup(JSON.stringify([other, group]), catalog)
    expect(result.status).toBe("updated")
    const written = JSON.parse((result as { text: string }).text)
    expect(written[0]).toEqual(other)
    expect(written[1].apiKey).toBe("${input:llmi}")
    expect(written[1].apiType).toBe("responses")
    expect(written[1].models).toEqual(catalog)
  })

  test("unchanged when the models already match", () => {
    expect(mergeGroup(JSON.stringify([{ ...group, models: catalog }]), catalog).status).toBe("unchanged")
  })

  test("no-group when the Custom Endpoint group does not exist (never creates one)", () => {
    expect(mergeGroup(JSON.stringify([other]), catalog).status).toBe("no-group")
    expect(mergeGroup("", catalog).status).toBe("no-group")
    expect(mergeGroup(JSON.stringify([{ ...group, vendor: "openai" }]), catalog).status).toBe("no-group")
  })

  test("refuses a group with a provider-level url (VS Code would ignore the models)", () => {
    expect(mergeGroup(JSON.stringify([{ ...group, url: "https://gw.test/v1" }]), catalog).status).toBe("discovery-url")
  })

  test("never replaces a working list with an empty one", () => {
    expect(mergeGroup(JSON.stringify([group]), []).status).toBe("invalid")
  })

  test("parse errors do not quote file content (it may hold a plaintext key)", () => {
    const result = mergeGroup('[{"apiKey": "SENTINEL-SECRET" oops', catalog)
    expect(result.status).toBe("invalid")
    expect(JSON.stringify(result)).not.toContain("SENTINEL")
  })

  test("keeps comments, trailing commas and other providers' text byte for byte", () => {
    const text = `[\n\t// my providers\n\t${JSON.stringify(other)}, // keep\n\t${JSON.stringify(group)},\n]\n`
    const result = mergeGroup(text, catalog)
    expect(result.status).toBe("updated")
    const written = (result as { text: string }).text
    expect(written).toContain("// my providers")
    expect(written).toContain(`${JSON.stringify(other)}, // keep`)
    expect(written.endsWith(",\n]\n")).toBe(true)
    expect(mergeGroup(written, catalog).status).toBe("unchanged")
  })

  test("refuses files it cannot parse instead of overwriting them", () => {
    expect(mergeGroup("[ {\"a\": ]", catalog).status).toBe("invalid")
    expect(mergeGroup("{}", catalog).status).toBe("invalid")
  })
})

describe("validCatalogResponses", () => {
  test("needs non-empty data arrays in both responses", () => {
    expect(validCatalogResponses(models, info)).toBe(true)
    expect(validCatalogResponses(models, {})).toBe(false)
    expect(validCatalogResponses({ data: [] }, info)).toBe(false)
    expect(validCatalogResponses(null, info)).toBe(false)
    expect(validCatalogResponses({ data: [...models.data, { name: "no id" }] }, info)).toBe(false)
    expect(validCatalogResponses(models, { data: [...info.data, { model_name: "x" }] })).toBe(false)
    expect(validCatalogResponses(models, { data: [...info.data, { model_name: "x", model_info: [] }] })).toBe(false)
    expect(validCatalogResponses(models, { data: [...info.data, { model_name: "", model_info: {} }] })).toBe(false)
  })
})

describe("toBudget", () => {
  test("reads spend and max_budget", () => {
    expect(toBudget({ spend: 12.5, max_budget: 200, pct_used: 6.25 })).toEqual({ spend: 12.5, max: 200 })
    expect(toBudget({ spend: "x" })).toBeUndefined()
  })
})
