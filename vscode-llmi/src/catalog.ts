import { applyEdits, modify, parse, type ParseError } from "jsonc-parser/lib/esm/main.js"

type JsonObject = Record<string, any>

export const GROUP_NAME = "AUMOVIO LLMi"

export type ApiType = "messages" | "responses" | "chat-completions"

export interface CustomEndpointModel {
  id: string
  name: string
  apiType: ApiType
  url: string
  toolCalling: boolean
  vision: boolean
  contextWindow: number
  maxOutputTokens: number
  statefulResponses?: false
}

/** Same split as the OpenCode llmi plugin: the API on which each family reads its prompt cache. */
export function apiTypeFor(id: string): ApiType {
  if (/^claude[-_]/i.test(id) || /\/claude[-_]/i.test(id)) return "messages"
  if (/^gpt[-_]/i.test(id) || /^o[134][-_]/i.test(id)) return "responses"
  return "chat-completions"
}

const PATHS: Record<ApiType, string> = {
  messages: "/v1/messages",
  responses: "/v1/responses",
  "chat-completions": "/v1/chat/completions",
}

function finite(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : undefined
}

/** Chat models that can call tools (agent mode hides the rest), from /v1/models and /v1/model/info. */
/** Both answers must be complete: one odd row could otherwise shrink a working list. */
export function validCatalogResponses(models: unknown, info: unknown): boolean {
  const data = (body: unknown): unknown[] | undefined => {
    const value = body && typeof body === "object" ? (body as JsonObject).data : undefined
    return Array.isArray(value) && value.length > 0 ? value : undefined
  }
  const modelRows = data(models)
  const infoRows = data(info)
  if (!modelRows || !infoRows) return false
  return (
    modelRows.every((row: any) => typeof row?.id === "string" && row.id) &&
    infoRows.every(
      (row: any) =>
        typeof row?.model_name === "string" &&
        row.model_name &&
        row.model_info &&
        typeof row.model_info === "object" &&
        !Array.isArray(row.model_info),
    )
  )
}

export function toModels(baseURL: string, models: JsonObject, info: JsonObject): CustomEndpointModel[] {
  const details = new Map<string, JsonObject>()
  for (const entry of Array.isArray(info?.data) ? info.data : []) {
    if (typeof entry?.model_name === "string" && entry.model_info && typeof entry.model_info === "object") {
      details.set(entry.model_name, entry.model_info)
    }
  }

  const result: CustomEndpointModel[] = []
  const seen = new Set<string>()
  for (const model of Array.isArray(models?.data) ? models.data : []) {
    if (typeof model?.id !== "string" || seen.has(model.id)) continue
    const detail = details.get(model.id) ?? {}
    if ((detail.mode ?? model.mode) !== "chat" || detail.blocked === true) continue
    if (detail.supports_function_calling === false) continue
    seen.add(model.id)

    const context = finite(detail.max_input_tokens) ?? finite(model.max_input_tokens) ?? 200_000
    let output = finite(detail.max_output_tokens) ?? finite(model.max_output_tokens) ?? 32_000
    if (output >= context) output = Math.floor(context / 2)
    const apiType = apiTypeFor(model.id)
    result.push({
      id: model.id,
      name: model.id,
      apiType,
      url: `${baseURL}${PATHS[apiType]}`,
      toolCalling: true,
      vision: detail.supports_vision === true,
      contextWindow: context,
      maxOutputTokens: output,
      ...(apiType === "responses" ? { statefulResponses: false as const } : {}),
    })
  }
  return result.sort((a, b) => a.id.localeCompare(b.id))
}

export type MergeResult =
  | { status: "updated"; text: string }
  | { status: "unchanged" }
  | { status: "no-group" }
  | { status: "discovery-url" }
  | { status: "invalid"; reason: string }

/**
 * Replaces only the `models` of the "AUMOVIO LLMi" Custom Endpoint group, as a range edit: comments,
 * formatting, the group's apiKey reference and every other provider stay as they are.
 */
export function mergeGroup(fileText: string, models: CustomEndpointModel[]): MergeResult {
  if (models.length === 0) return { status: "invalid", reason: "gateway returned no usable models" }
  const errors: ParseError[] = []
  // No parser error text in the result: it can quote file content, and the file may hold a plaintext key.
  const providers: unknown = fileText.trim() ? parse(fileText, errors, { allowTrailingComma: true }) : []
  if (errors.length > 0) return { status: "invalid", reason: "syntax error" }
  if (!Array.isArray(providers)) return { status: "invalid", reason: "top level is not an array" }
  const index = providers.findIndex(
    (entry) => entry && typeof entry === "object" && entry.name === GROUP_NAME && entry.vendor === "customendpoint",
  )
  if (index < 0) return { status: "no-group" }
  const group = providers[index]
  // A provider-level url switches VS Code to its own discovery and ignores `models`.
  if (typeof group.url === "string" && group.url) return { status: "discovery-url" }
  if (JSON.stringify(group.models) === JSON.stringify(models)) return { status: "unchanged" }
  const indent = /^ +"/m.exec(fileText)?.[0].length
  const edits = modify(fileText, [index, "models"], models, {
    formattingOptions: indent ? { insertSpaces: true, tabSize: Math.min(indent, 4) } : { insertSpaces: false, tabSize: 1 },
  })
  return { status: "updated", text: applyEdits(fileText, edits) }
}

export interface Budget {
  spend: number
  max: number
}

export function toBudget(body: JsonObject): Budget | undefined {
  const spend = typeof body?.spend === "number" ? body.spend : undefined
  const max = typeof body?.max_budget === "number" ? body.max_budget : undefined
  return spend !== undefined && max !== undefined ? { spend, max } : undefined
}
