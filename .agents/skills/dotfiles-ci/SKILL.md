---
name: dotfiles-ci
description: Use when CI fails in the dotfiles repo, or before pushing changes to shell scripts, test/*.sh, ./install or ./run, to reproduce the GitHub Actions lint and keys jobs locally, or when writing tests in test/install-only.sh (fakes, FAKE_* switches, root skips). Covers shellcheck findings that appear only in CI, macOS-only test failures, the known Ubuntu 26.04 libgcrypt failure, and './run ci:test' being blocked.
---

# Dotfiles CI

## Jobs and what may fail

| Workflow | Job | Runs | Notes |
|---|---|---|---|
| `ci.yml` | Test Linting and Testing | `./run ci:test`: shellcheck, shfmt, ruff | Runner's shellcheck is **0.9.0**; info-level findings fail the job |
| `ci.yml` | Keys phase (ubuntu-24.04, archlinux, macos) | `bash test/deps.sh`, `bash test/keys.sh`, `bash test/install-only.sh` | macOS uses BSD tools and brew bash; Linux jobs run as root in containers |
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
  $(git ls-files -z | xargs -0 grep -l -E '^(#!.*sh|# shellcheck shell=)')
shfmt --diff . .config/zsh/.{aliases,zprofile,zshrc}
ruff check && ruff format --check --diff
KEYS_TESTS="t1_work_pc_fresh t10_renewed_in_public" bash test/keys.sh   # subset; omit for all
ONLY_TESTS="t_wsl_installs t_tmux_updates" bash test/install-only.sh     # subset; t_ prefix required
bash test/wiki.sh
bash test/ai-inventory.sh
```

To check an older commit, run the same commands in a worktree:
`git worktree add /tmp/opencode/ci-SHA SHA`, then `git worktree remove` it.
To only read a file as it was, `git show SHA:path` is enough.

## `test/install-only.sh` (`./install --only` pieces)

Hermetic: each `run_install NAME ARGS...` gets a fresh `HOME`, a repo copy
and fake commands first on `PATH`. Every fake appends `<cmd> <args>` to the
call log; tests assert with `called` / `not_called` (ERE over that log).
`KEEP=1` keeps the temp dir (`NAME.log`, `NAME.calls`) after a failure.

| Need | Use |
|---|---|
| Pick the OS | `scenario debian\|arch\|macos\|wsl` at the start of the test |
| Make a fake exit non-zero | `FAKE_EXIT_<NAME>=N`, name upper-cased, non-alphanumerics to `_` (`tasklist.exe` → `FAKE_EXIT_TASKLIST_EXE`, `apt-get` → `FAKE_EXIT_APT_GET`) |
| Any other scenario switch | a `FAKE_*` variable: `run_install` forwards all of them through `env -i`; nothing else gets through |
| Stable vs nightly WezTerm present | `FAKE_STABLE=1`, `FAKE_NIGHTLY=1` |
| Set up `HOME` before the run | `PRE=func run_install ...`; `func` gets the home dir as `$1` |
| Test that needs non-root (WSL, Arch/makepkg) | first line `skip_if_root "why" \|\| return 0`; Linux CI is root and prints "skipped (root)" |
| A new fake | `write_fake NAME 'sh body'` in `write_fakes` |

Fakes model reality, not convenience:

- A fake must not do what the real command does not. Example: real `curl -o`
  makes a non-executable file, so the fake does not `chmod +x`; the code
  under test must. A helpful fake hides exactly the bug the test is for.
- The fake `sudo` runs the rest only if it is another fake; real commands
  (`mkdir /etc/...`) are only logged.
- A failure test must fail at the step it claims (fail `apt-get install`,
  not the earlier `apt-get update`), and assert the dangerous step did not
  run (`not_called 'pacman -R'`).
- Hashing works on macOS too: `sha256sum` if present, else `shasum -a 256`.

## Portability traps (macOS job)

| Trap | Use instead |
|---|---|
| `[ "$(... \| wc -l)" = 1 ]`: BSD `wc` pads with spaces | `-eq 1`, or `grep -c` |
| `A && B \|\| fail` (SC2015) | `[[ A && B ]] \|\| fail` |
| Backticks inside single-quoted `sed` (SC2016) | `# shellcheck disable=SC2016 # literal backticks` above the line |
| GNU-only flags (`sed -i`, `date -d`, `readlink -f`) | portable form or a helper |

macOS cannot be run here; push and watch the macOS job to confirm.
