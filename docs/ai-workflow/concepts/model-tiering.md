---
title: Model tiering for agents
created: 2026-11-19
updated: 2026-11-19
type: concept
tags: [models, cost, subagent, opencode]
sources: [https://opencode.ai/docs/agents/, https://opencode.ai/docs/console/go/]
confidence: medium
---

# Model tiering for agents

Two tiers, chosen per agent:

| Tier | How it is set | Used for | Agents (2026-11-19) |
|---|---|---|---|
| **Inherit** | No `model` field; the subagent uses the parent session's model | Judgement: reviews, analysis, upgrade mapping | `cpp-reviewer`, `investigator`, `release-mapper` |
| **Cheap** | `model: opencode-go/deepseek-v4.1-flash` in the agent file | Mechanical work: run and summarize, draft text, fetch tickets | `build-runner`, `scribe`, `jira`, `confluence` |
| **Cheap (built-in)** | `agents.<id>.model` in both `opencode.json` and `opencode_work.json` | Summarizing context, read-only search | `compaction`, `explore` |

Built-in agents are overridden in JSON, not with an `agents/<id>.md` file:
a file body would replace the built-in system prompt. `general` stays on
inherit: it does multi-step work where a weak model costs more in retries.

Reviewers stay one per language (`cpp-reviewer` today) rather than one
generic reviewer (user decision 2026-11-19).

## Why

- Inherit keeps the strong-model decision in one place (the session) and
  follows upgrades automatically.
- The cheap tier is the third test in [[when-to-use-a-subagent]]. Prices
  checked 2026-11-19: DeepSeek V4.1 Flash $0.15/$0.60 per M tokens in/out;
  DeepSeek V4 Pro about 4x that. Prefer a stronger model if it costs a bit
  more but saves retries.

## Work vs personal

Decided 2026-11-19: no provider restriction for work code, so both configs
use the same cheap model and it lives in the agent file. If that changes,
move `model` out of the agent files and set `agents.<id>.model` per config
file (`opencode.json` vs `opencode_work.json`); agent settings merge by ID.

## Team repos

Never put a model ID in a file committed to a team repo: teammates may not
have that provider. Team repos get skills only; see
[[2026-11-19-agents-global-skills-project]].

## Open questions

- No local benchmark yet of cheap models on these tasks; revisit if
  `scribe` or `build-runner` summaries are often wrong.
