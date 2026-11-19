# Wiki Log

> Chronological record of wiki actions. Append-only.
> Format: `## [YYYY-MM-DD] action | subject`
> Actions: create, update, query, lint, archive, delete

## [2026-11-19] create | Wiki initialized

- Domain: working with AI coding agents (OpenCode V2, Copilot, Codex, Claude Code)
- Created: SCHEMA.md, index.md, log.md
- Pages: concepts/when-to-use-a-subagent, concepts/agent-skill-command,
  concepts/model-tiering, concepts/cross-tool-locations,
  decisions/2026-11-19-agents-global-skills-project
- Source: design session, spec `docs/superpowers/specs/2026-11-19-ai-workflow-design.md`

## [2026-11-19] create | Plugin layers and essential plugins
- Pages: concepts/plugin-layers, decisions/2026-11-19-essential-plugins
- Config: cc-safety-net and opencode-quota added, compaction.auto true; cli.json re-linked to dotfiles
- Source: plugin research session (awesome-opencode, opencode.im, npm tarballs, opencode.ai docs)

## [2026-11-19] update | Project skills added

- sw.sys.libcontidms `eqs_develop` efbfd17c4: `.agents/skills/pipeline-analysis`
  (force-added: the repo's `.gitignore` ignores `.agents/`)
- sw.sys.dmsd `denali4.1_eqs_es10` 67aaa18a: `.agents/skills/config-audit`
- sw.tool.cabinvue `main` c1aa891: `.agents/skills/interface-contracts`
- Pages touched: none; matches [[2026-11-19-agents-global-skills-project]]
