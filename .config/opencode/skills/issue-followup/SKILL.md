---
name: issue-followup
description: Use when deferring work to a GitHub issue, or when reading, replying to or agreeing the contract of an agent-followup issue before working on it.
---

# Issue follow-ups

Deferred work lives in a GitHub issue. The user comments there between
sessions; the agent replies in a later session; both agree on the
`## Contract` before any code is written. Uses `gh` in the repo.
Only for repos with a GitHub remote (`gh repo view` works); elsewhere skip.
Other sessions share `/tmp/opencode`, so write drafts to a fresh directory,
`D=$(mktemp -d /tmp/opencode/issue.XXXX)`, never to fixed file names.

## Labels

`agent-followup` on every such issue, plus one state label:
`contract:draft` (still being discussed) or `contract:agreed`.
Create missing labels before first use (safe to repeat):

```bash
gh label create agent-followup --color 5319e7 --description "Deferred by the agent" --force
gh label create contract:draft --color fbca04 --description "Contract under discussion" --force
gh label create contract:agreed --color 0e8a16 --description "Contract agreed, ready to plan" --force
```

## File

When work is deferred, offer to file an issue; create it only after the
user says yes in the session. Show the title and body first.

Body template:

```markdown
## Context
What the problem is, where (file:line), how it was found.

## Tried
What was tried or ruled out, and why. "Nothing yet" is fine.

## Why deferred
Missing hardware, data, decision, or out of scope for the current task.

## Contract
- **Scope:** what will change, and what will not.
- **Approach:** the intended fix, or open options.
- **Prerequisites:** what must exist first.
- **Done when:** checkable criteria (tests, measurements, demo).

### Changes
- YYYY-MM-DD: drafted.
```

```bash
gh issue create --title "..." --body-file "$D/issue-body.md" \
  --label agent-followup --label contract:draft
```

## Find and read

At the start of a task in the repo:

```bash
gh issue list --label agent-followup --state open
```

List only the titles that touch the task; do not dump every body. For
each relevant one, read the whole thread:

```bash
gh issue view N --json title,body,labels,comments \
  --jq '.title, (.labels|map(.name)|join(",")), .body, (.comments[]|"--- "+.author.login+":\n"+.body)'
```

(Plain `gh issue view N --comments` prints only the comments when the
output is not a terminal, so the body and labels would be missing.)

The user's comments override the body. Agent comments (they start with
`> 🤖 agent reply`) are earlier agent replies, not user decisions.

## Reply

`gh` posts as the user, so every agent comment starts with the marker
line. One comment per session round, covering all open points; no
comment just to acknowledge. Post only after the user said yes to
replying in this session.

```markdown
> 🤖 agent reply

Answers to the open questions, proposed contract changes, new questions.
```

```bash
gh issue comment N --body-file "$D/reply.md"
```

## Update the contract

When a point is agreed, edit only the `## Contract` section (including
`### Changes`, one dated line per update). Read the current body right
before editing and keep every other section exactly as it is, including
the user's own edits:

```bash
gh issue view N --json body --jq .body > "$D/body.md"
# edit only ## Contract in body.md
gh issue edit N --body-file "$D/body.md"
```

`--body-file` replaces the whole body: fetch again just before the edit,
and if the body changed meanwhile, re-apply only the contract change to
the new text.

## Agree and implement

Only the user moves the issue to agreed, or tells the agent to:

```bash
gh issue edit N --remove-label contract:draft --add-label contract:agreed
```

Do not implement while the label is `contract:draft`; discuss instead.
With `contract:agreed`, the contract is the approved design: skip the
brainstorming round and go to `writing-plans` with the issue as the spec.
If implementation shows the contract is wrong in a way that changes
scope, approach or done criteria, stop: tell the user, move the label
back to `contract:draft`, and propose the change (comment only after
their yes, as in Reply). Resume only after they agree again. The PR says
`Fixes #N`.
