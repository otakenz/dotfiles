export const ANTHROPIC_PACKAGE = "@opencode/ai/providers/anthropic-compatible"
export const RESPONSES_PACKAGE = "@opencode/ai/providers/openai-compatible/responses"

type JsonObject = Record<string, any>

export interface DiscoveredModel {
  id: string
  modelID: string
  name: string
  package?: string
  capabilities: { tools: boolean; input: string[]; output: string[] }
  variants: never[]
  time: { released: number }
  cost: Array<{ input: number; output: number; cache: { read: number; write: number } }>
  status: "active"
  enabled: boolean
  limit: { context: number; input?: number; output: number }
}

export function runtimePackage(id: string): string | undefined {
  if (/^claude[-_]/i.test(id) || /\/claude[-_]/i.test(id)) return ANTHROPIC_PACKAGE
  if (/^gpt[-_]/i.test(id) || /^o[134][-_]/i.test(id)) return RESPONSES_PACKAGE
  return undefined
}

function finite(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined
}

/** Stable identity of an OpenCode connection, so an account switch can be detected. */
export function connectionKey(
  connection: { type: "credential"; id: string } | { type: "env"; name: string },
): string {
  return connection.type === "credential" ? `credential:${connection.id}` : `env:${connection.name}`
}

function perMillion(value: unknown): number {
  return Math.round((finite(value) ?? 0) * 1e12) / 1e6
}

/** Maps only public model metadata. Never copy litellm_params or model_info wholesale. */
export function toInventory(models: JsonObject, info: JsonObject): DiscoveredModel[] {
  const details = new Map<string, JsonObject>()
  for (const entry of Array.isArray(info.data) ? info.data : []) {
    if (typeof entry?.model_name === "string" && entry.model_info && typeof entry.model_info === "object") {
      details.set(entry.model_name, entry.model_info)
    }
  }

  const inventory: DiscoveredModel[] = []
  for (const model of Array.isArray(models.data) ? models.data : []) {
    if (typeof model?.id !== "string") continue
    const detail = details.get(model.id) ?? {}
    const mode = detail.mode ?? model.mode
    if (mode !== "chat" || detail.blocked === true) continue

    const context = finite(detail.max_input_tokens) ?? finite(model.max_input_tokens) ?? 200_000
    const output = finite(detail.max_output_tokens) ?? finite(model.max_output_tokens) ?? 32_000
    const hasPrice = finite(detail.input_cost_per_token) !== undefined || finite(detail.output_cost_per_token) !== undefined

    inventory.push({
      id: model.id,
      modelID: model.id,
      name: model.id,
      package: runtimePackage(model.id),
      capabilities: {
        tools: detail.supports_function_calling !== false,
        input: detail.supports_vision === true ? ["text", "image"] : ["text"],
        output: ["text"],
      },
      variants: [],
      time: { released: (finite(model.created) ?? 0) * 1000 },
      cost: hasPrice
        ? [
            {
              input: perMillion(detail.input_cost_per_token),
              output: perMillion(detail.output_cost_per_token),
              cache: {
                read: perMillion(detail.cache_read_input_token_cost),
                write: perMillion(detail.cache_creation_input_token_cost),
              },
            },
          ]
        : [],
      status: "active",
      enabled: true,
      limit: { context, input: context, output },
    })
  }
  return inventory
}
