# Dotfiles

- `~/.config/opencode` (agents, skills, commands, `AGENTS.md`) is symlinked
  into this checkout, so live OpenCode sessions read whatever is checked out
  here. Several sessions often work in this repo at the same time.
- For multi-commit work (a feature branch, a plan), use a separate git
  worktree instead of switching branches in `~/dotfiles`, so other sessions
  neither commit onto your branch nor lose files when you switch. Test agent
  or skill changes that must be live from `~/dotfiles` only after merging,
  or say so before switching branches here.
- Before merging, fetch and rebase onto `main`: other sessions push to it
  directly.
