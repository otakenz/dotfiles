import * as vscode from "vscode"
import { lstat, open, readFile, rename, unlink } from "node:fs/promises"
import { randomUUID } from "node:crypto"
import { dirname, join } from "node:path"
import { userInfo } from "node:os"
import { GROUP_NAME, mergeGroup, toBudget, toModels, validCatalogResponses } from "./catalog"

const BASE_URL = "https://llm-gateway.ve42034x.automotive-wan.com"
const SECRET = "llmi.apiKey"

/** Error text safe to log or show: never raw exceptions, which can quote headers or file content. */
class SafeError extends Error {}

function describe(error: unknown): string {
  if (error instanceof SafeError) return error.message
  if (error instanceof Error && error.name === "TimeoutError") return "gateway timed out (company network or VPN?)"
  if (error instanceof TypeError) return "gateway not reachable (company network or VPN?)"
  return "unexpected error"
}

async function readText(file: string): Promise<string> {
  try {
    return await readFile(file, "utf8")
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return ""
    throw new SafeError(`cannot read ${file}`)
  }
}

export function activate(context: vscode.ExtensionContext) {
  const log = vscode.window.createOutputChannel("LLMi", { log: true })
  const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100)
  status.command = "llmi.refresh"
  context.subscriptions.push(log, status)

  const config = () => vscode.workspace.getConfiguration("llmi")

  /** chatLanguageModels.json of the default profile: the User folder, two levels above global storage. */
  const modelsFile = () =>
    config().get<string>("languageModelsFile") ||
    join(dirname(dirname(context.globalStorageUri.fsPath)), "chatLanguageModels.json")

  const get = async (path: string, key: string) => {
    const response = await fetch(`${BASE_URL}${path}`, {
      headers: { Authorization: `Bearer ${key}` },
      signal: AbortSignal.timeout(10_000),
    })
    if (!response.ok) throw new SafeError(`${path.split("?")[0]}: HTTP ${response.status}`)
    try {
      return await response.json()
    } catch {
      throw new SafeError(`${path.split("?")[0]}: response is not JSON`)
    }
  }

  /**
   * Best effort against lost edits: stage a private temp file next to the target, then, right before
   * the rename, skip if an editor holds unsaved changes or the file changed since it was read.
   */
  const writeIfUnchanged = async (file: string, before: string, text: string) => {
    // rename would replace a symlink itself and cut the config off from its real target.
    const link = await lstat(file).then((stat) => stat.isSymbolicLink(), () => false)
    if (link) throw new SafeError(`${file} is a symlink; set llmi.languageModelsFile to its target`)
    const temp = `${file}.llmi-${randomUUID()}.tmp`
    let created = false
    try {
      const handle = await open(temp, "wx", 0o600)
      created = true
      try {
        await handle.writeFile(text, "utf8")
        await handle.sync()
      } finally {
        await handle.close()
      }
      const dirty = vscode.workspace.textDocuments.some((doc) => doc.isDirty && doc.uri.fsPath === file)
      if (dirty) throw new SafeError("chatLanguageModels.json has unsaved changes in an editor; save it, then refresh")
      if ((await readText(file)) !== before) throw new SafeError("chatLanguageModels.json changed meanwhile; refresh again")
      await rename(temp, file)
      created = false
    } catch (error) {
      throw error instanceof SafeError ? error : new SafeError(`cannot write ${file}`)
    } finally {
      if (created) await unlink(temp).catch(() => {})
    }
  }

  let running: Promise<void> | undefined
  let queued: Promise<void> | undefined
  const refresh = (interactive: boolean): Promise<void> => {
    if (running) {
      if (!interactive) return running
      // A manual refresh or a new key must not just join an older run; all clicks share one follow-up.
      return (queued ??= running.then(() => {
        queued = undefined
        return refresh(true)
      }))
    }
    running = sync(interactive).finally(() => (running = undefined))
    return running
  }

  const fail = (message: string, interactive: boolean) => {
    log.error(message)
    status.text = "$(error) LLMi"
    status.tooltip = `LLMi: ${message}`
    status.command = "llmi.refresh"
    status.show()
    if (interactive) void vscode.window.showErrorMessage(`LLMi: ${message}`)
  }

  const sync = async (interactive: boolean) => {
    try {
      const key = await context.secrets.get(SECRET)
      if (!key) {
        status.text = "$(key) LLMi"
        status.tooltip = "LLMi: no API key. Click to set it."
        status.command = "llmi.setKey"
        status.show()
        if (interactive) void vscode.commands.executeCommand("llmi.setKey")
        return
      }
      status.command = "llmi.refresh"
      const [models, info] = await Promise.all([get("/v1/models", key), get("/v1/model/info", key)])
      if (!validCatalogResponses(models, info)) throw new SafeError("gateway returned an unexpected model list; kept the current one")
      const catalog = toModels(BASE_URL, models, info)

      const file = modelsFile()
      const before = await readText(file)
      const merged = mergeGroup(before, catalog)
      if (merged.status === "invalid") throw new SafeError(`${file}: ${merged.reason}; not changed`)
      if (merged.status === "discovery-url") {
        throw new SafeError(`remove the "url" line from the "${GROUP_NAME}" group in ${file}; with it VS Code ignores the model list`)
      }
      if (merged.status === "no-group") {
        status.text = "$(warning) LLMi"
        status.tooltip = `Add the Custom Endpoint group "${GROUP_NAME}" first (see the guide).`
        status.show()
        log.warn(`no Custom Endpoint group named "${GROUP_NAME}" in ${file}`)
        if (interactive) {
          void vscode.window
            .showWarningMessage(
              `LLMi: add a Custom Endpoint group named "${GROUP_NAME}" with your key first, then run "LLMi: Refresh Models".`,
              "Manage Language Models",
            )
            .then((pick) => pick && vscode.commands.executeCommand("workbench.action.chat.manage"))
        }
        return
      }
      if (merged.status === "updated") {
        await writeIfUnchanged(file, before, merged.text)
        log.info(`wrote ${catalog.length} models to ${file}`)
      } else {
        log.info(`${catalog.length} models, no change`)
      }
      if (interactive) void vscode.window.showInformationMessage(`LLMi: ${catalog.length} models up to date.`)
      await showBudget(key, catalog.length)
    } catch (error) {
      fail(describe(error), interactive)
    }
  }

  const showBudget = async (key: string, count: number) => {
    status.text = "LLMi"
    status.tooltip = `LLMi: ${count} models. Click to refresh.`
    const user = config().get<string>("userId") || userInfo().username.toLowerCase()
    try {
      const budget = toBudget(await get(`/v1/budget/status?user_id=${encodeURIComponent(user)}`, key))
      if (budget) {
        status.text = `LLMi $${budget.spend.toFixed(2)} / $${budget.max.toFixed(0)}`
        status.tooltip = `LLMi budget for ${user}: $${budget.spend.toFixed(2)} of $${budget.max.toFixed(2)} spent. ${count} models. Click to refresh.`
      }
    } catch (error) {
      log.warn(`budget: ${describe(error)}`)
    }
    status.show()
  }

  let timer: ReturnType<typeof setInterval> | undefined
  const schedule = () => {
    if (timer) clearInterval(timer)
    const minutes = config().get<number>("refreshMinutes") ?? 15
    timer = minutes > 0 ? setInterval(() => void refresh(false), minutes * 60_000) : undefined
  }

  context.subscriptions.push(
    vscode.commands.registerCommand("llmi.setKey", async () => {
      const key = await vscode.window.showInputBox({
        title: "LLMi API key",
        prompt: "From https://llmi-hub.ai2ans.aws.automotive.cloud/llm-token. Stored in VS Code secret storage.",
        password: true,
        ignoreFocusOut: true,
        validateInput: (value) => (/^[\x21-\x7e]+$/.test(value.trim()) ? undefined : "Paste the key only (no spaces)"),
      })
      if (!key?.trim()) return
      await context.secrets.store(SECRET, key.trim())
      await refresh(true)
    }),
    vscode.commands.registerCommand("llmi.refresh", () => refresh(true)),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("llmi.refreshMinutes")) schedule()
    }),
    { dispose: () => timer && clearInterval(timer) },
  )

  schedule()
  void refresh(false)
}

export function deactivate() {}
