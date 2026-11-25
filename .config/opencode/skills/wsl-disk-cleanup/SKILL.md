---
name: wsl-disk-cleanup
description: Use when WSL or a Linux home feels bloated, the disk is filling up, the user asks what can be removed to free space (caches, Docker images, old projects, toolchains, apt packages), Windows does not get the space back, or a WSL distro should be backed up (export, OneDrive).
---

# WSL disk cleanup

Find what is no longer used, prove it, and hand the user a list with
commands. You delete only the items the user names.

## 1. Survey

Run `bash scan.sh` from this folder (read-only, about 30 s; `bash scan.sh 2G`
for less). It never reads `/mnt/*`; do not search the Windows drives.

- Dates are the newest file inside a folder. Ignore atime: relatime and apt
  upgrades reset it.
- `df` higher than `du`: root-owned data such as `/var/lib/docker`. Trust
  `docker system df` for Docker.

## 2. Evidence per candidate

An item is unused only with evidence. Check, for each:

| Kind | Proof it is in use |
|---|---|
| Any folder or model | running `systemctl --user` services, `pgrep`, configs that name it (`grep -r` in dotfiles, `~/.config`, repos) |
| Git working copy | `git status`, `git log @{u}..`, branches without upstream, `git stash list`, untracked secrets (`.env`); git-ignored big dirs: how README/Makefile regenerates them |
| Docker image | a repo under `~` that builds or runs it (`grep -rl <name> ~ --include='*.hcl' --include=Makefile --include='*Dockerfile*' --include='*.py' --include='*.json' --include='*.yml' --exclude-dir={.git,.venv,node_modules,_deps,build,.cache,.local,pkg}`, CI workflows included); a Dockerfile `FROM`; the newest tag of a self-built image is current. Tags with one ID free space only together. Docker keeps no last-used date |
| Toolchain | `rustup toolchain list`: keep `default` and `active` (`RUSTUP_TOOLCHAIN` can differ); mise config vs `mise ls`; conda env history date |
| Shared blob cache (Hugging Face) | delete only blobs no kept model links to |

"Probably unused" needs a fact that shows disuse: a config or commit
that switched away, the owning repo gone, the user said so. Age, a newer
sibling or "nothing references it" are guesses: put those under "Ask".
An older image or toolchain can be a supported platform (Ubuntu 20).

## 3. Report

One table per class, each row: path or name, size, evidence, command.

1. **Safe**: caches that rebuild (`uv cache clean`, `bun pm cache rm`,
   `pip cache purge`, `npm cache clean --force`, `micromamba clean -a`,
   `docker builder prune -a`).
2. **Probably unused**: with the evidence.
3. **Ask**: duplicates, recordings, backups, unclear purpose.
4. **Keep**: in use, so nobody asks again.

Leave out empty classes. End with the total for 1 and 2; for Docker use
`docker system df` RECLAIMABLE, since layers are shared.

## 4. Removing

- Commands use absolute paths: `rm -rf ~/playgrounds/old_x`, never
  `cd ..; rm -rf name` (one wrong `cd` deletes the neighbour).
- Before removing a git copy, show what step 2 found lost vs regenerable.
- Measure with `df -h /` before and after; report freed space from that.
- Windows gets the space back only when the VHDX shrinks: once
  `wsl --manage <distro> --set-sparse true` (WSL shut down), or
  `Optimize-VHD`. Sparse does not return space freed before the switch,
  so it finishes at once: run `sudo fstrim -av` in WSL afterwards, and
  after big deletions. Check with the VHDX "Size on disk", not "Size".

## Backup

Export, formats, C: space and OneDrive: see `backup.md` in this folder.

## Recovering an accidental `rm -rf`

No Trash, and ext4 undelete is hopeless with TRIM. Restore instead: clone
from the remote (find the URL in `$HISTFILE`),
check the last local commit was pushed (OpenCode sessions:
`~/.local/share/opencode/opencode.db`, table `session`, column `directory`),
then regenerate the ignored dirs with the repo's own prepare step and list
what is gone for good (backups, `.env`).
