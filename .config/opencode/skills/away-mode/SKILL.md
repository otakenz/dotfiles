---
name: away-mode
description: Use when the user says they will be away for a while (hours, overnight, days) and wants work to continue without them - decide instead of asking, keep a checkpoint file with decisions, checkpoints and blockers, and stop only for dangerous or truly blocking steps.
---

# Away mode

The user is away. Keep working through the agreed scope; they read one file
when they return.

## Checkpoint file

`~/away/<YYYY-MM-DD>-<repo or topic>.md`, created at the start; tell the
user its path before they leave. Layout, newest information at the top:

```markdown
# Away: <scope>   (started <date time>, last update <date time>)

## When you're back
- Done: <one line per finished item, with commit/PR>
- Decide: <decisions taken that you may want to revisit, link to the log line>
- Waiting for you: <publishing, merges, hardware at the bench, credentials>
- Blockers: <what, why, what was tried, what would unblock>

## Log
- <time> CHECKPOINT <task>: <state>, <commit>, <evidence/report path>
- <time> DECISION <topic>: chose <X> over <Y> because <reason>; undo: <how>
- <time> BLOCKER <topic>: <symptom>; tried <...>; moved on to <...>
```

Update it after every task, decision and blocker, not only at the end. Keep
the "When you're back" section current, so it reads as a summary at any
moment.

## Deciding without asking

- Do not use the question tool and do not end a turn waiting for an answer.
  Take the option you would have recommended, log it as DECISION with the
  reason and how to undo it, and continue.
- Where a skill says "ask the user" or "get approval", the same: decide,
  log, continue. Brainstorming: write the design yourself from earlier
  conversation, specs and code; mark open questions in the spec.
- Prefer reversible choices: a new commit over a history rewrite, a flag
  that is off by default over changed behaviour, a branch over `main`.
- Reviews, tests and verification still run as usual; away mode removes
  the waiting, not the checks.

## Stop only for

Log as BLOCKER, then continue with the next independent item. Stop the whole
run only if nothing independent is left.

- Irreversible or destructive steps: force-push or rewriting pushed
  history, deleting work you did not create, wiping or reformatting data,
  flashing or anything that needs a person at the hardware to recover.
- Security-sensitive steps: credentials, keys, permissions, firewall,
  disabling checks.
- Publishing to shared places: merging into shared branches, tags and
  releases, Confluence/Jira/Slack writes, emails. Push to your own feature
  branches and open draft PRs; prepare the rest (page files, PR text, tag
  commands) and list it under "Waiting for you".
- Spending money or quota far beyond the task.

## Practical rules

- GPG signing: try signed commits. If signing fails (locked agent, no
  pinentry), commit unsigned, log it once, and list the unsigned commits
  under "Waiting for you" so they can be re-signed before merging.
- Hardware: leave it in a safe state after every session (power off,
  unmount); never leave a bench powered while waiting.
- Infrastructure hiccups (host reboot, network): retry a few times with
  pauses, check the obvious cause, log it, work on something that does not
  need it meanwhile.
- Long runs: background them; do not poll. Use timers or automations for
  checks at a later time.

## Delegated work: watchdog

When the first subagent starts long work (hardware sessions, builds, test
matrices, deploys), create one watchdog automation for this session:

- Trigger every 10 minutes, `expires` within 3 days; a prompt to this
  session. One per session, not one per subagent.
- The prompt checks activity with one shell call: newest commit, files
  changed in the last 15 minutes under the work folder, the task ledger and
  `/tmp/opencode`, and running build, test or hardware processes. Add the
  project's own signs if its skill names them.
- Stale (nothing changed for 15 minutes and no such process): send the
  subagent (by sessionID) a ping for a 3-line status, continue or report
  BLOCKED; log a line in the checkpoint file. Otherwise reply only
  `watchdog: ok`. The watchdog never starts new work.
- The work folder is the repo or worktree the subagent works in. A ping
  joins the subagent's current run; it does not interrupt it.
- Delete it when no delegated work is left or the user is back; note its id
  in the checkpoint file. `expires` cleans up if this session dies.

## Delegated work: fail fast and timeouts

Every brief for long or repeated runs includes:

- Precondition errors (missing input, wrong deployed version, unreachable
  host, broken environment) stop the whole run at once.
- The same error on two consecutive items stops the run. Retry only
  infrastructure errors (network, host), once, after a pause.
- Timeouts as named constants derived from measured durations (typical time
  times 2, at least 30 s extra), with the measurement in a comment; a budget
  for the whole run as well as per item.
- Integrity checks hash an explicit allowlist of inputs, never files the run
  itself writes.
- After a stop, keep the finished items' results, list the stopped and
  remaining ones, and record which can resume without a rerun.
- Context: before the conversation gets compacted, make sure the checkpoint
  file and the repo's plan or ledger hold everything needed to resume.
