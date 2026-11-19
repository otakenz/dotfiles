---
title: When to use a subagent
created: 2026-11-19
updated: 2026-11-19
type: concept
tags: [subagent, context, cost, opencode]
sources: [https://opencode.ai/docs/agents/]
confidence: high
---

# When to use a subagent

A subagent runs in a child session with a **fresh context**, its **own
permissions** and optionally its **own model**. Only its final report comes
back to the parent. Each of those three properties is a reason to use one;
if none applies, a subagent only adds cost and loses context.

## The three tests

Make something a subagent only if it passes at least one:

1. **Noisy output**: it produces lots of build logs, test logs or command
   output where only a summary matters. The noise stays in the child.
   Example: `build-runner`.
2. **Strict limits**: it should be read-only or have a narrowed shell, so a
   mistake cannot change anything. Example: `cpp-reviewer`, `investigator`.
3. **Cheaper model**: a smaller model can do the job. Example: `scribe`,
   `jira`. See [[model-tiering]].

## When not to

- The main conversation needs the details, not just the result: use a skill
  instead ([[agent-skill-command]]).
- It is a persona ("python-pro", "backend-developer"): current models already
  know the language. Persona collections such as
  VoltAgent/awesome-claude-code-subagents are useful to read, not to install.
- The parent would have to re-explain a lot of context in the prompt: the
  child starts from zero.

## Notes

- A fresh context is also a fresh pair of eyes: reviewers benefit from not
  having seen the author's reasoning.
- Keep the agent list short. Every subagent's `description` is shown to the
  parent model when it decides what to delegate.

Related: [[agent-skill-command]], [[model-tiering]],
[[2026-11-19-agents-global-skills-project]].
