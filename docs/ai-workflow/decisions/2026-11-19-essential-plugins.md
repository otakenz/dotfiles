---
title: Essential plugins for OpenCode V2
created: 2026-11-19
updated: 2026-11-19
type: decision
tags: [opencode, security, context, cost]
sources: [https://opencode.ai/docs/compaction/, https://ccsafetynet.com/docs/installation/opencode, https://github.com/slkiser/opencode-quota, https://github.com/Opencode-DCP/opencode-dynamic-context-pruning]
confidence: high
---

# Essential plugins for OpenCode V2

## Context

Local, single-user development through three providers: `opencode-go`,
`github-copilot` and the company `aumovio-llmi` gateway. Wanted: the
essential plugins only, no SaaS, nothing V2 or the model already does. See
[[plugin-layers]] for the layer model.

## Options per layer

| Layer | Chosen | Rejected and why |
|---|---|---|
| Workflow | **superpowers** (already installed) | oh-my-opencode: overlaps; V2 support "unknown" on opencode.im |
| Memory | **opencode-mem** (already installed; local vector store) | supermemory: SaaS |
| Context | **V2 built-in compaction**, `compaction.auto: true` | DCP: see below |
| Safety | **cc-safety-net** 2.7.15 | envsitter-guard: covers `.env` only |
| Observability | **@slkiser/opencode-quota** 6.3.0 | madsoftwaredev usage: cost only, no quota limits |
| Subagent UX, notifications | none | built into V2 |
| Provider auth | none | Copilot is built in; LLMi is a custom provider |

### Why not DCP (Dynamic Context Pruning)

`@tarquinen/opencode-dcp` 3.2.1 does run on V2 (dual package with a `v2`
entry), but:

- It rewrites old messages before each request, which **breaks prompt-cache
  prefixes**. opencode-go and LLMi bill tokens, so uncached prefill costs
  more and is slower. V2 compaction reuses the cache.
- It adds a `compress` tool, its system prompt and periodic nudges, so the
  session model spends tokens and turns on housekeeping.
- Defaults nudge compression from 100k tokens, far below the 1M windows in
  use.
- It would be a second context manager next to V2 compaction.
- `autoUpdate: true` by default; upstream says development has slowed in
  favor of Sleev (a proxy).

## Verification (2026-11-19, OpenCode 2.3.2)

- cc-safety-net: peer `@opencode/plugin ^2.0.6`; docs list 2.0.6+. Uses the
  `posix` dialect by default on Linux (zsh is fine). Network only from its
  CLI (npm version check, rulebook fetch from GitHub), none in the plugin.
- opencode-quota: peer `@opencode/plugin >=2.0.28`; Node 22.13+ (local
  Node 24). Built-in providers include GitHub Copilot and OpenCode Go.
  Contacts only the providers' quota APIs and models.dev for prices.
- No telemetry found in either npm tarball.

## Decision

Made by the user, 2026-11-19. Both `opencode.json` and `opencode_work.json`:

- `plugins`: superpowers, opencode-mem, cc-safety-net, opencode-quota.
- `compaction.auto: true`, default buffer (15% of the window). The earlier
  `buffer: 10000` would compact at ~99% on 1M-token models.

## Consequences

- cc-safety-net blocks `git reset --hard`, `git push --force`, risky `rm -rf`
  and reads of SSH keys and `.env` files **even when asked**; run those
  yourself in a shell.
- LLMi has no quota API; the quota plugin shows its token usage only. A
  `local-estimate` custom provider is possible once a real limit is known.
- Quota settings live in `~/.config/opencode/opencode-quota/settings.jsonc`
  (machine-local, not in the dotfiles).
- `cli.json` must stay a symlink to the dotfiles. On 2026-11-18 the link was
  found replaced by a regular file (mode 600) holding newer settings, most
  likely written by the TUI settings dialog; edit the dotfiles copy instead.
