# LLMi models in VS Code

The VS Code counterpart of the OpenCode `llmi` plugin
(`.config/opencode/plugins/llmi/`): LLMi is its own model provider in VS Code
chat (next to GitHub Copilot), and its models follow the gateway on their own.

- Every 15 minutes (and on **LLMi: Refresh Models**) it reads `/v1/models` and
  `/v1/model/info` and rewrites the models of the Custom Endpoint group
  **AUMOVIO LLMi** in `chatLanguageModels.json`. VS Code reloads that file by
  itself.
- Per model it sets the API on which the prompt cache works, like the plugin:
  Claude → Messages, GPT → Responses (stateless), others → Chat Completions.
  Context and output limits, vision and tool support come from the gateway:
  `contextWindow` is the gateway's `max_input_tokens` (as in the OpenCode
  plugin), from which VS Code subtracts the output allowance; when
  `max_output_tokens` reaches that value, the output cap is halved.
  Chat models without tool calling are left out (agent mode hides them).
- The status bar shows the LLMi budget (`/v1/budget/status`); click it to
  refresh.
- VS Code itself sends the chat requests (built-in Custom Endpoint provider);
  this extension only maintains the model list.

## Keys

The extension never writes a key into a file. It needs the LLMi key twice,
both kept in VS Code secret storage:

1. **Manage Language Models → Add Models → Custom Endpoint**, group name
   exactly `AUMOVIO LLMi`, paste the key. This is the key chat uses; VS Code
   writes only a `${input:…}` reference into `chatLanguageModels.json`.
2. **LLMi: Set API Key**: the key the extension uses to read the model list
   and budget.

The extension only replaces the group's `models` (a range edit: comments
and other providers stay; whitespace next to `models` may be reformatted); it never creates the group.
It leaves the file untouched, and logs to the **LLMi** output channel, when:

- the file has a syntax error;
- the group has a provider-level `url` (VS Code would then ignore the list);
- the gateway answer is empty or has malformed rows (the last list stays);
- the file is a symlink (set `llmi.languageModelsFile` to its target);
- an editor holds unsaved changes to the file, or it changed since it was
  read (checked right before the write; best effort, not a lock).

Writes go to a private temp file next to the target, then a rename.

Settings are user-level only (a workspace cannot redirect the write), and
the extension never reads workspace files, so it also runs in untrusted
workspaces (Restricted Mode). They
apply to all profiles: `llmi.languageModelsFile` selects one target file for
the whole installation. Needs
VS Code 1.147 or later; it runs on the local UI side.

## Settings

| Setting | Default | |
|---|---|---|
| `llmi.refreshMinutes` | 15 | 0 = only at startup and on demand |
| `llmi.userId` | login name | LLMi user id for the budget |
| `llmi.languageModelsFile` | User folder | for a non-default VS Code profile: the path of the file VS Code opens from *Manage Language Models* |

## Build

```sh
bun install
bun run check     # typecheck + unit tests
bun run package   # -> llmi-models-<version>.vsix
code --install-extension llmi-models-0.1.0.vsix
```
