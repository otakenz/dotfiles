---
title: Plugin layers
created: 2026-11-19
updated: 2026-11-19
type: concept
tags: [opencode, security, context, cost]
sources: [https://opencode.ai/docs/plugins/, https://opencode.ai/docs/build/plugins/migrate-v1/, https://opencode.ai/docs/compaction/, https://opencode.ai/docs/cli/config/, https://opencode.im/rankings, https://github.com/awesome-opencode/awesome-opencode]
confidence: medium
---

# Plugin layers

A plugin setup works best as **one plugin per layer**. Plugins in the same
layer overlap and compete (two workflow frameworks both steer the agent; two
context managers both rewrite history). Fill a layer only when OpenCode V2 or
the model does not already cover it.

## The layers

| Layer | What it does | Popular choices (2026-11) | Covered by V2 itself? |
|---|---|---|---|
| Workflow | How the agent plans, tests, reviews | Superpowers, oh-my-opencode(-slim) | No (plan agent only) |
| Memory | Facts that survive across sessions | opencode-mem, supermemory (SaaS) | No |
| Context | Keep long sessions under the window | DCP, compaction-model | **Yes**: compaction, background summaries, `agents.compaction.model` |
| Safety | Block destructive commands and secret reads | cc-safety-net, envsitter-guard | Partly: `permissions` rules, `.env` asks by default |
| Observability | Quota, tokens, cost | opencode-quota, madsoftwaredev usage/stats | Partly: `session.tps`, `debug.turn_tokens` |
| Subagent UX | Background subagents, sidebar | madsoftwaredev background-subagent | **Yes**: `subagent` supports background runs |
| Notifications | Alert when a run ends or waits | agent-notifications, ntfy.sh | **Yes**: `attention` in `cli.json` |
| Provider auth | Use another subscription | antigravity/gemini/codex/cursor auth | Copilot, ChatGPT built in; the rest are unofficial (ToS risk) |

Also built in as of 2.3.2 (`opencode plugin list --builtin`): goals, todos,
snapshots/undo, web search, `/btw` side questions, worktrees.

## Finding plugins

There is no official registry. awesome-opencode is a curated list but does
not mark V2 support. [opencode.im](https://opencode.im/plugins) filters by
"V2 with evidence" and ranks by stars and npm downloads.

## Checking V2 compatibility

V1 plugin code does not run in V2 (the plugin API changed). Check before
adding:

1. `npm view <pkg> peerDependencies`: V2 plugins depend on
   `@opencode/plugin` (V2); `@opencode-ai/plugin` alone means V1 only.
2. A dual package may list only the V1 peer but ship a V2 entry
   (`Plugin.define`, `lib/v2/`); look inside with `npm pack`.
3. After adding it, `opencode plugin list` must show it loaded.

Never use `opencode plugin add` here: it rewrites `opencode.json`, which is a
symlink into the dotfiles. Edit the dotfiles config instead; OpenCode
installs missing packages on reload.

## Related

- [[2026-11-19-essential-plugins]]: the plugins chosen for this setup
- [[agent-skill-command]]: when to build your own instead of adding a plugin
- [[model-tiering]]

## Open questions

- Write our own small plugins under `.opencode/plugins/` once a recurring
  need shows up (V2 API: `Plugin.define` + `setup(ctx)`).
