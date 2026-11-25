# Global instructions

These apply to every OpenCode session on this machine. Project `AGENTS.md`
files add to them.

## Skills and subagents: add on purpose

- Before creating a skill or subagent, check whether an existing one can be
  extended instead. Prefer extending.
- A new subagent must pass at least one test:
  1. **Noisy output**: lots of logs or command output where only a summary
     matters.
  2. **Strict limits**: it should be read-only or have a narrowed shell.
  3. **Cheaper model**: a smaller model can do the job reliably.
  If none applies, it should be a skill (the conversation needs the details)
  or nothing.
- Project know-how goes into the repo's `AGENTS.md` and
  `.agents/skills/<name>/SKILL.md` (read by OpenCode, Copilot and Codex),
  not into a personal agent. The `name` must equal the folder name.
- Keep these tool-neutral: frontmatter only `name` and `description`, no
  personal agent or tool names in the text. For Claude Code, add
  `CLAUDE.md` containing `@AGENTS.md` and symlink
  `.claude/skills -> ../.agents/skills`; never copy the content.
- If an inventory of agents and skills exists (see personal instructions),
  add every new agent or skill to it in the same change.

## Suggest, don't sprawl

At the end of a task, add one line when it applies:

- A procedure was repeated or project facts were explained again: suggest a
  skill.
- A step flooded the context, needed strict limits, or was mechanical
  enough for a cheaper model: suggest a subagent.
- An agent or skill looked unused, overlapping or stale: suggest removing or
  merging it.
- The repo has no `AGENTS.md` and the task showed its build, layout or
  conventions well enough: suggest a short one (every-task facts only;
  procedures go into skills).

Suggest only; never create or delete agents, skills or `AGENTS.md` files
without being asked.
