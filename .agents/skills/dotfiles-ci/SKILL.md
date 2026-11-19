---
name: dotfiles-ci
description: Use when CI fails in the dotfiles repo, or before pushing changes to shell scripts, test/*.sh, ./install or ./run, to reproduce the GitHub Actions lint and keys jobs locally. Covers shellcheck findings that appear only in CI, macOS-only test failures, the known Ubuntu 26.04 libgcrypt failure, and './run ci:test' being blocked.
---

# Dotfiles CI

## Jobs and what may fail

| Workflow | Job | Runs | Notes |
|---|---|---|---|
| `ci.yml` | Test Linting and Testing | `./run ci:test`: shellcheck, shfmt, ruff | Runner's shellcheck is **0.9.0**; info-level findings fail the job |
| `ci.yml` | Keys phase (ubuntu-24.04, archlinux, macos) | `bash test/deps.sh`, `bash test/keys.sh` | macOS uses BSD tools and brew bash |
| `ci.yml` | Keys phase (ubuntu-26.04) | same | `known_issue: true`, so it may fail without failing the run (libgcrypt 1.12.0, LP #2174038, "Bad secret key") |
| `install.yml` | Full install (4 platforms) | `test/install-prep.sh`, `./install`, `test/install-check.sh` | ~10 min |

`test/wiki.sh` and `test/ai-inventory.sh` are not in CI; run them by hand.

## Read a failure

```bash
gh run list --limit 5
gh run view RUN --json jobs -q '.jobs[]|"\(.conclusion) \(.name)"'
gh run view RUN --log-failed | grep -E 'FAIL|SC[0-9]+ \(|In \./'   # only after the run completes
```

If the run is red, some job other than ubuntu-26.04 keys failed (the
allowance is `continue-on-error` with `known_issue` in `ci.yml`). Compare
with the last green run (`gh run list --workflow ci.yml`) to find the
commit that broke it.

A keys `FAIL tN_name: message` prints the test's own `fail` text. Find the
assertion with `grep -n "message" test/keys.sh`, then check it against the
portability traps below before suspecting `./install`. Lines in the
machine logs (`m10.log` etc.) are often warnings, not the cause.

## Reproduce locally

`./run ci:test` (and any `./run` task) may be refused by the agent safety
net because `run` contains an `rm -rf` in another task. Run the steps
directly; use the CI shellcheck version, a newer local one misses findings
(e.g. SC2015):

```bash
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:v0.9.0 \
  $(git ls-files -z -- ':!mnt/c' | xargs -0 grep -l -E '^(#!.*sh|# shellcheck shell=)')
shfmt --diff . .config/zsh/.{aliases,zprofile,zshrc}
ruff check && ruff format --check --diff
KEYS_TESTS="t1_work_pc_fresh t10_renewed_in_public" bash test/keys.sh   # subset; omit for all
bash test/wiki.sh
bash test/ai-inventory.sh
```

To check an older commit, run the same commands in a worktree:
`git worktree add /tmp/opencode/ci-SHA SHA`, then `git worktree remove` it.
To only read a file as it was, `git show SHA:path` is enough.

## Portability traps (macOS job)

| Trap | Use instead |
|---|---|
| `[ "$(... \| wc -l)" = 1 ]`: BSD `wc` pads with spaces | `-eq 1`, or `grep -c` |
| `A && B \|\| fail` (SC2015) | `[[ A && B ]] \|\| fail` |
| Backticks inside single-quoted `sed` (SC2016) | `# shellcheck disable=SC2016 # literal backticks` above the line |
| GNU-only flags (`sed -i`, `date -d`, `readlink -f`) | portable form or a helper |

macOS cannot be run here; push and watch the macOS job to confirm.
