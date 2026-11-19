# Wiki Schema

Path: `~/dotfiles/docs/ai-workflow`. `WIKI_PATH` is deliberately not set (it
would redirect `~/wiki/cabinvue-wiki`); point the `llm-wiki` skill at this
path explicitly when maintaining it.

## Domain

Lessons and decisions from working with AI coding agents: OpenCode V2 first,
plus GitHub Copilot, Codex and Claude Code where they interact. Covers agents,
subagents, skills, commands, permissions, model choice and cost, and where
each tool reads its files. Applied to the user's dotfiles and their DMS
project repos.

## Conventions

- File names: lowercase, hyphens. Decision pages start with the date:
  `decisions/YYYY-MM-DD-<slug>.md`.
- Every page starts with the frontmatter below.
- Link pages with double-bracket wikilinks to the file name without `.md`
  (e.g. `when-to-use-a-subagent`); at least 2 outbound links per page.
- Bump `updated` on every edit. Add new pages to `index.md`. Append every
  action to `log.md`.
- Keep pages readable in a minute; split anything over ~200 lines.
- No `raw/` folder: vendor docs go stale and are not copied. Cite their URLs
  in `sources:` and re-check them when a page is revisited.

## Frontmatter

```yaml
---
title: Page Title
created: YYYY-MM-DD
updated: YYYY-MM-DD
type: concept | decision
tags: [from taxonomy below]
sources: [https://...]
confidence: high | medium | low   # optional
---
```

## Page types

- **concept**: how something works or a rule of thumb. Sections: what it
  is, current understanding, open questions, related pages.
- **decision**: one choice, ADR style. Sections: context, options with
  trade-offs, decision and who made it, consequences. Never rewritten after
  the fact; a later decision supersedes it and links back.

## Tag taxonomy

Add a tag here before using it.

- Tools: `opencode`, `copilot`, `codex`, `claude-code`
- Mechanisms: `subagent`, `skill`, `command`, `instructions`, `permissions`
- Concerns: `models`, `cost`, `context`, `layout`, `portability`, `security`

## Update policy

When a newer source contradicts a page: note both claims with dates, set
`confidence: low` until resolved, and log it. Tool behavior changes between
versions, so record the version or date a claim was checked.
