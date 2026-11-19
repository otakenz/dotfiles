---
title: Agents global and personal, skills in project repos
created: 2026-11-19
updated: 2026-11-19
type: decision
tags: [layout, subagent, skill, portability, opencode, copilot]
sources: [https://opencode.ai/docs/agents/, https://code.visualstudio.com/docs/agents/reference/custom-agent-file-reference]
confidence: high
---

# Agents global and personal, skills in project repos

## Context

The team uses GitHub Copilot and OpenCode on shared repos (libcontidms, dmsd,
cabinvue, ...). OpenCode and Copilot read agents from different folders with
different frontmatter ([[cross-tool-locations]]), but both read
`.agents/skills/`. The user wanted project-specific helpers usable by the
team, without double maintenance.

## Options

| Option | Trade-off |
|---|---|
| A. Skill body in `.agents/skills/`, thin agent wrappers per tool in each repo | One source of truth; two wrapper files per agent per repo |
| B. One source + generator writing both agent formats | Native files; generated files in team repos, drift when someone edits an output |
| C. Hand-written duplicate agent files per tool | Simple; double maintenance |
| D. Agents global in dotfiles; only skills in project repos | No duplication in team repos; agents are personal |

## Decision

**D**, chosen by the user. Seven global subagents in
`dotfiles/.config/opencode/agents/` (tiers in [[model-tiering]]); project
know-how as skills: `pipeline-analysis` (libcontidms), `config-audit`
(dmsd), `interface-contracts` (cabinvue), next to the existing
`build-visualizer` and `deploy-dmsd-hdk`.

## Consequences

- Teammates get the skills inline in Copilot or OpenCode with no setup.
- The user gets them through subagents: `investigator` loads the matching
  skill in a fresh, read-only context.
- Skills must stand alone: no references to personal agents.
- No model IDs in team repos.
- Committed directly to each repo's base branch, no PR (user decision).

Related: [[when-to-use-a-subagent]], [[agent-skill-command]].
