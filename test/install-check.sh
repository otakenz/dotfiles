#!/usr/bin/env bash
# Checks what `./install` (phase 1) must leave behind. Run after the install,
# as the same user, in a fresh shell.

set -o nounset

status=0
fail() {
  printf "FAIL: %s\n" "${*}" >&2
  status=1
}
ok() { printf "ok:   %s\n" "${*}"; }

for prefix in /opt/homebrew /usr/local; do
  [ -x "${prefix}/bin/brew" ] && eval "$("${prefix}/bin/brew" shellenv)"
done
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:${PATH}"
export GNUPGHOME="${HOME}/.config/gnupg"
dotfiles="${DOTFILES_PATH:-${HOME}/dotfiles}"

for link in .zshenv .config/zsh/.zshrc .config/git/config .config/gnupg/gpg.conf \
  .config/gnupg/gpg-agent.conf .config/tmux/tmux.conf .config/nvim; do
  if [ -L "${HOME}/${link}" ]; then ok "symlink ~/${link}"; else fail "${HOME}/${link} is not a symlink"; fi
done

for cmd in zsh git gpg gopass mise nvim tmux; do
  if command -v "${cmd}" >/dev/null 2>&1; then ok "${cmd} on PATH"; else fail "${cmd} not found"; fi
done

if [ -z "$(gpg --list-secret-keys --with-colons 2>/dev/null)" ]; then
  ok "no GPG secret key created"
else
  fail "phase 1 created a GPG secret key"
fi

if [ -f "${HOME}/.ssh/id_ed25519" ]; then ok "personal SSH key"; else fail "${HOME}/.ssh/id_ed25519 missing"; fi

config_local="${dotfiles}/.config/git/config.local"
if [ -z "$(git config --file "${config_local}" user.signingkey 2>/dev/null)" ]; then
  ok "config.local has no signingkey"
else
  fail "config.local already names a signing key"
fi
if git config --file "${config_local}" core.sshCommand | grep -q 'id_ed25519 '; then
  ok "config.local uses the personal SSH key"
else
  fail "config.local sshCommand: $(git config --file "${config_local}" core.sshCommand)"
fi

exit "${status}"
