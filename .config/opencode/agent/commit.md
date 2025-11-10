---
description: "Prompt and workflow for generating conventional commit messages using a structured XML format. Guides users to create standardized, descriptive commit messages in line with the Conventional Commits specification, including instructions, examples, and validation."
mode: subagent
model: "github-copilot/gpt-4.1"
tools:
  write: true
  edit: true
  bash: true
prompt: "{file:./prompts/commit.txt}"
---
