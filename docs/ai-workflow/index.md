# AI Workflow Wiki Index

> What has been learned about working with AI coding agents, and why things
> are set up the way they are. Read this first. Conventions: [SCHEMA.md](SCHEMA.md).
> Last updated: 2026-11-19 | Total pages: 7

## Concepts

- [[agent-skill-command]]: which mechanism for what (primary agent, subagent, skill, command, instructions)
- [[cross-tool-locations]]: where OpenCode, Copilot, Codex and Claude Code read agents and skills
- [[model-tiering]]: inherit vs cheap model per agent, work vs personal, no models in team repos
- [[plugin-layers]]: one plugin per layer, what V2 already covers, how to check V2 compatibility
- [[when-to-use-a-subagent]]: the three tests (noisy output, strict limits, cheaper model)

## Decisions

- [[2026-11-19-agents-global-skills-project]]: agents stay personal and global, project know-how goes into shared skills
- [[2026-11-19-essential-plugins]]: superpowers, opencode-mem, cc-safety-net, opencode-quota; built-in compaction instead of DCP
