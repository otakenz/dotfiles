---
title: Where each tool reads agents and skills
created: 2026-11-19
updated: 2026-11-19
type: concept
tags: [opencode, copilot, codex, claude-code, portability, layout]
sources: [https://opencode.ai/docs/agents/, https://opencode.ai/docs/skills/, https://code.visualstudio.com/docs/agents/reference/custom-agent-file-reference, https://code.visualstudio.com/docs/agent-customization/agent-skills, https://docs.github.com/en/copilot/concepts/agents/about-agent-skills]
confidence: high
---

# Where each tool reads agents and skills

Checked 2026-11-19 (OpenCode 2.3.2, VS Code docs of 2026-11-18).

## Agents (tool-specific)

| Tool | Project | User | Format |
|---|---|---|---|
| OpenCode | `.opencode/agents/<id>.md` | `~/.config/opencode/agents/<id>.md` | `description`, `mode`, `model` (`provider/model#variant`), ordered `permissions` |
| GitHub Copilot | `.github/agents/<name>.agent.md` | `~/.copilot/agents/` | `name`, `description`, `tools` list (`read`, `search`, `edit`, `execute`, ...), `model` |
| Claude Code | `.claude/agents/<name>.md` | `~/.claude/agents/` | `name`, `description`, `tools` comma list, `model` (`sonnet`/`opus`/`haiku`/`inherit`) |

No folder or frontmatter is shared, so one agent file cannot serve OpenCode
and Copilot. Copilot also reads `.claude/agents` in the Claude format.

## Skills (shared standard)

| Folder | OpenCode | Copilot | Codex | Claude Code |
|---|---|---|---|---|
| `.agents/skills/<id>/SKILL.md` | yes | yes | yes (native) | no |
| `.github/skills/` | no | yes (preferred) | via VS Code integration | no |
| `.claude/skills/` | yes | yes | no | yes |
| `.opencode/skills/` | yes | no | no | no |

`.agents/skills/` is the widest overlap for the tools the team uses. Rules
that make a skill load everywhere:

- `name` equals the folder name, lowercase kebab-case, max 64 characters.
  Copilot silently drops mismatches.
- `description` says what it does **and when to use it** (max 1024
  characters); without it OpenCode does not advertise the skill.

## OpenCode notes

- V2 still reads V1 folders (`agent/`, `command/`) but `agents/` and
  `commands/` are preferred.
- After creating a new agents folder or symlink, the file watcher may miss
  it; `opencode api post /api/location/reload` picks it up.
- Permission action for MCP tools is `<server>_<tool>` with unsupported
  characters turned into `_`.

Related: [[agent-skill-command]], [[2026-11-19-agents-global-skills-project]].
