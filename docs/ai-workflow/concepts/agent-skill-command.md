---
title: Agent, skill or command
created: 2026-11-19
updated: 2026-11-19
type: concept
tags: [subagent, skill, command, instructions, opencode, copilot]
sources: [https://opencode.ai/docs/agents/, https://opencode.ai/docs/skills/, https://code.visualstudio.com/docs/agent-customization/agent-skills]
confidence: high
---

# Agent, skill or command

| Mechanism | What it is | Runs where | Pick it when |
|---|---|---|---|
| **Primary agent** | The main working profile (`build`, `plan`) | Main session | Almost never custom: override `build` with permission rules instead of writing a new one |
| **Subagent** | Profile: permissions + model + fresh context | Child session | It passes one of the tests in [[when-to-use-a-subagent]] |
| **Skill** | Know-how: a procedure, checklist, scripts | Loaded into the current context on demand | The conversation needs the steps or the details |
| **Command** | A prompt template the user fires | Main session (or a subagent if configured) | You start the same request by hand often |
| **Instructions** (`AGENTS.md`) | Always-on rules | Every session in that directory | Project conventions that always apply |

## Rule of thumb

- If the conversation needs the **context**, write a skill.
- If it only needs the **result**, use a subagent.
- Agents decide *how safely and how cheaply*; skills decide *what to do*. A
  subagent can load a skill, so the two combine: `investigator` +
  `pipeline-analysis`.

## Portability

Skills follow the open Agent Skills format (`SKILL.md` with `name` and
`description`) and are read by OpenCode, Copilot and Codex. Agent files are
tool-specific. That difference drives the layout in
[[2026-11-19-agents-global-skills-project]]; paths are in
[[cross-tool-locations]].

## Primary agents in practice

`build` and `plan` cover most work. Custom primaries make sense for a distinct
mode you switch into (a docs writer, a review-only mode). Otherwise add rules
to the built-in, e.g. ask before `git push *` in `build`.
