# dotfiles

[![CI](https://github.com/otakenz/dotfiles/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/otakenz/dotfiles/actions/workflows/ci.yml)
[![Install](https://github.com/otakenz/dotfiles/actions/workflows/install.yml/badge.svg?branch=main)](https://github.com/otakenz/dotfiles/actions/workflows/install.yml)

- **CI:** lint, plus the keys-pass and `./install --only` tests on Ubuntu 24.04, Ubuntu 26.04, Arch and macOS, on every push
- **Install:** the full first-pass install on the same four platforms, weekly and when `install` changes

Welcome to my dotfiles! This is a collection of my personal tools and
configurations for a productive development environment. My whole setup can be
configured in mere minutes through a single **install** script. This setup is
cater for me to work efficiently on multiple platforms, including Windows (WSL2),
Ubuntu, Archlinux.

If you would like to try it out, you can do so in a Docker container without
modifying your machine. This is a great way to test it out before installing it
on your machine. Instruction is provided below.

## 📓Supported platforms

- Archlinux
- Ubuntu 22+
- macOS (tested on Apple Silicon macOS 15)
- wsl2 (Archlinux/ Ubuntu22+)

## 🔗 Requirements

- git
- curl
- bash 4+ (macOS needs to install bash 4+ via brew as it ships with bash 3.2,
  before running the install script)
- [Docker](https://docs.docker.com/engine/install/) (for experience it or local test)
- [PowerToys](https://github.com/microsoft/PowerToys) (For Windows, to swap esc and caps key bind)

## 🔨 Installation

macOS install bash 4+ first

```sh
# Apple silicon macOS
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
  && eval "$(/opt/homebrew/bin/brew shellenv)" \
  && brew install bash \
  && bash
```

### Local way

```sh
git clone https://github.com/otakenz/dotfiles.git
cd ~/dotfiles
LOCAL=1 bash install
```

### Remote way

```sh
rm /tmp/install 2>/dev/null || true && curl -sS https://raw.githubusercontent.com/otakenz/dotfiles/master/install -o /tmp/install \
&& chmod +x /tmp/install && bash /tmp/install
```

Add `--work-pc` on a work machine (both passes). It also creates a separate work SSH key.

## 🔑 Keys and gopass (second pass)

The first pass does **not** create a GPG key. Your GPG identities live in an offline backup, and
the second pass restores them, so that you keep one identity across all your machines. Run it once
the first pass has finished:

1. **Register the SSH keys** the first pass printed. The personal key goes to github.com (and
   gitlab.com), the work key to the work Git host. Never put the same key on both: GitHub publishes
   every account's keys at `github.com/<user>.keys`, which would link the accounts.
2. **Bring the key backup folder** onto the machine (copy it, or mount the drive), e.g.
   `~/key-backup`.
3. **Run the keys pass** in a new terminal:

   ```sh
   ~/dotfiles/install --keys ~/key-backup            # personal machine
   ~/dotfiles/install --keys ~/key-backup --work-pc  # work machine
   ```

4. **Publish the updated public key** on each GitHub account. Until then, commits from this machine
   show as _Unverified_. GitHub cannot update a key in place, so delete the old entry and add the
   new block. The script prints these commands with the right host, key ID and file filled in:

   ```sh
   gh auth refresh -h github.com -s admin:gpg_key   # once per host: lets gh change GPG keys
   gh gpg-key delete <last 16 hex of the fingerprint> --yes
   gh gpg-key add ~/key-backup/personal-public.asc --title personal
   ```

   For the work host, prefix the last two with `GH_HOST=<work host>`. Or use the host's
   _Settings → SSH and GPG keys_ page.
5. **Copy `*-public.asc` back** to the offline backup, and delete the folder if it was a copy.

What `--keys` does, per identity (personal always, work with `--work-pc`):

- imports `<id>-secret.asc` and `<id>-public.asc`, plus that key's line of `ownertrust.txt`
- adds **this machine's signing subkey** (expires with the encryption subkey)
- keeps only the shared encryption subkey and the new signing subkey, then removes the primary key
  again: `gpg -K` shows `sec#`
- tests an encrypt/decrypt roundtrip, then writes the updated `<id>-public.asc` back into the folder
- turns on commit and tag signing, and clones the gopass stores

If any step fails, it removes that identity from the keyring entirely, so the primary key never
stays behind; a second Ctrl-C cannot interrupt that clean-up. Fix the cause and run the same
command again. Running it again on a machine that is already set up changes nothing. It refuses to
run against a keyring that already holds the primary (e.g. your offline machine).

**Backup folder**

| File                       | Read by `--keys` | Contains                                      |
| -------------------------- | ---------------- | --------------------------------------------- |
| `<id>-secret.asc`          | yes              | primary + shared encryption, no signing ¹     |
| `<id>-public.asc`          | yes              | latest published block, every signing subkey  |
| `ownertrust.txt`           | yes              | ultimate trust for your own keys              |
| `<id>-primary.asc`         | no               | primary only: renewals, new UIDs, revocation  |
| `<id>-revocation.rev`      | no               | kill switch; keep it offline, never in cloud  |

¹ Only what no machine can recreate. Every signing secret, the first machine's included, stays on
its machine, which is why `<id>-secret.asc` does not change when machines are added or keys
renewed: their public halves and the expiry dates live in `<id>-public.asc`, and `--keys` uses the
newest date from either file. Export it as `gpg --armor --export-secret-keys "$FPR!" "$E_FPR!"`
(`!` = exactly that key). An older backup that still holds a signing secret also works: `--keys`
drops it.

**Paths**

| What                     | Where                                                         |
| ------------------------ | ------------------------------------------------------------- |
| GPG keyring              | `~/.config/gnupg` (`GNUPGHOME`, exported by `.zprofile`)      |
| gopass config            | `~/.config/gopass/config`                                     |
| Personal store (root)    | `~/.local/share/gopass/stores/personal`                       |
| Work store (mount `work`)| `~/.local/share/gopass/stores/work`                           |
| Unattended store (mount `work-unattended`) | `~/.local/share/gopass/stores/work-unattended` (this machine only) |
| Store remotes            | `GOPASS_PERSONAL_URL` (default: this account's `gopass-store`), `GOPASS_WORK_URL` (asked if unset) |
| Git identity             | `~/.config/git/config.local`; on a work PC personal repos include `config.local.personal` |
| SSH keys                 | `~/.ssh/id_ed25519` (personal), `~/.ssh/id_ed25519_work` (work) |

Entries read `github/pat` in the personal store and `work-unattended/jira-pat` in the
unattended store:

```sh
gopass ls              # every store as one tree
gopass show -o PATH    # password only
gopass sync            # pull and push every store
```

**Unattended work store (work PC)**

`--keys --work-pc` also creates a key without a passphrase on this machine and a local store,
`work-unattended`, encrypted to it. It holds only tokens that background tools must read
without a prompt: the Jira and Confluence PATs, which mcp-atlassian fetches with
`gopass show`, and the LLMi key. The key can only encrypt, never signs, and has no git remote
and no backup. Every machine gets its own key and its own tokens: after the keys pass, create
fresh tokens and `gopass insert work-unattended/<name>` each one, as the script prints.
Rotating a token is `gopass edit work-unattended/<name>`; revoke a machine's tokens when you
retire it. Anything running as you can read this store, so keep everything else in `work`.

> **Ubuntu 26.04:** its libgcrypt 1.12.0 randomly rejects valid imported cv25519 keys with
> "Bad passphrase" ([LP #2174038](https://bugs.launchpad.net/bugs/2174038)). The keys pass warns
> about it. Update `libgcrypt20` to 1.12.1 or newer before importing.

The model behind it (why the encryption subkey is shared and signing subkeys are per machine,
rotation, restore) is in [`docs/key-management.pdf`](docs/key-management.pdf).

## Experience it

**Try it out in Docker without modifying your system:**

```sh
# Start a Debian container, we're passing in an env var to be explicit we're in Docker.
docker container run --rm -it --env-file .env -e "IN_CONTAINER=1" -v "${PWD}:/app" -w /app debian:stable-slim bash

# Copy / paste all 3 lines into the container's prompt and run it.
#
# Since we can't open a new terminal in a container we'll need to manually
# launch zsh and source a few files. That's what the last line is doing.
apt-get update && apt-get install -y curl \
  && bash <(curl -sS https://raw.githubusercontent.com/otakenz/dotfiles/master/install) \
  && zsh -c ". ~/.config/zsh/.zprofile && . ~/.config/zsh/.zshrc; zsh -i"
```

**Local Test with docker**

```sh
git clone https://github.com/otakenz/dotfiles.git
cd ~/dotfiles

docker container run --rm -it --env-file .env -e "IN_CONTAINER=1" -v "${PWD}:/app" -w /app debian:stable-slim bash

# Local test only
apt-get update && apt-get install -y curl \
  && LOCAL=1 bash install \
  && zsh -c ". ~/.config/zsh/.zprofile && . ~/.config/zsh/.zshrc; zsh -i"
```

_Keep in mind with the Docker set up, unless your terminal is already
configured to use Tokyonight Moon then the colors may look off. That's because
your local terminal's config will not get automatically updated._

## 📝 Install script

The install script will setup the following on your system:

### 1. [wezterm](https://wezterm.org/index.html) (cross platform GPU accelerated terminal)

#### [Ubuntu/Archlinux]

- WezTerm nightly (apt `wezterm-nightly` / AUR `wezterm-nightly-bin`; macOS: cask `wezterm@nightly`); an installed stable WezTerm is replaced
- Config wezterm at ~/.config/wezterm/wezterm.lua

#### [Windows/WSL2]

- New Wezterm nightly application installed on C:\Program Files\WezTerm by downloading the checksum-verified `WezTerm-nightly-setup.exe`
  > [Why nightly](#13-wezterm-on-windows-must-be-nightly)
- Config wezterm for windows is copied to %USERPROFILE%/.wezterm.lua.
  > Refer [ordering to this](https://wezterm.org/config/files.html)
- Optionally, if you don't want to copy the config file to %USERPROFILE%/.wezterm.lua, you can edit the properties of wezterm shortcut from startup menu.

```sh
# In "Target" field of WezTerm shortcut properties, specify the --config-file as follow:
"C:\Program Files\WezTerm\wezterm-gui.exe" \
  --config-file \\wsl.localhost\<REPLACE_DISTRO_NAME>\home\<REPLACE_USERNAME>\dotfiles\.config\wezterm\wezterm.lua
```

- Then you can pin the shortcut to the taskbar, the caveat is that the automatic hot-reload of config is broken with this method, and you have to manual-reload everytime with "CTRL+SHIFT+R"

### 2. [Powerlevel10k](https://github.com/romkatv/powerlevel10k) (Terminal theme)

- p10k configure (when needed to reconfigure)
- ~/.config/zsh/.p10k.zsh (config stored here)

### 3. [Meslo Nerd Font](https://www.nerdfonts.com/font-downloads) (Terminal Fonts that support icons)

- I used Meslo Nerd Font Mono and Symbols Nerd Font Mono, if you used otherwise, you have to modify your wezterm.lua

#### [Ubuntu/Archlinux]

- Fonts data installed at ~/.local/share/fonts/
- fc-cache -fv (load new fonts to terminal)

#### [Window/WSL2]

- You have to install Nerd Fonts manually
- Unzip the installed NerdFonts to %USERPROFILE%/.local/share/fonts
- Choose the fonts style and click "install"

### 4. zsh (Modern Terminal Shell)

- ~/.config/zsh/.zshrc (zsh configurations)
- ~/.config/zsh/.zshrc (to add machine specifics config)
- ~/.config/zsh/.zprofile (zsh profile run on login)
- ~/.config/zsh/.zprofile.local (to add machine specifics profile)
- ~/.config/zsh/.zsh_history (commands history stored here)

```sh
# To append old history to new
cat ~/.bash_history >> ~/.config/zsh/.zsh_history
```

- ~/.zshenv (zsh environment globally)
- ~/.config/zsh/.aliases
- ~/.config/zsh/.aliases.local (store your local aliases here)

### 5. [mise](https://mise.jdx.dev/getting-started.html) (language/package manager, better asdf)

```sh
# To view installed packages
mise ls
# To install new package globally (user-wide), specify 'latest' if no specific version requirement
mise use -g <package>@<version>
# To list available versions of a package
mise list-all <package>
```

- node@24, python@3.13, go@latest, lua@5.1.5, rust@nightly

### 6. CLI Tools (special mentioned)

- [bat](https://github.com/sharkdp/bat) (better cat, provide colors)
- [delta](https://github.com/dandavison/delta) (provide syntax highlighting for git, diff)
- [eza](https://github.com/eza-community/eza) (better ls, with color and icons)
- [fd](https://github.com/sharkdp/fd) (find on steroids, ultra fast files search)
- [fzf](https://github.com/junegunn/fzf) (fuzzy finder)
- [gitui](https://github.com/gitui-org/gitui) (git TUI, written in rust, can be spawned inside neovim)
- [lazygit](https://github.com/jesseduffield/lazygit) (another git TUI, written in go, can be spawned inside neovim)
- [ripgrep](https://github.com/BurntSushi/ripgrep) (ultra fast regex search on files)
- [tldr](https://github.com/tldr-pages/tldr) (cheatsheet for console commands)
- [uv](https://github.com/astral-sh/uv) (An extremely fast Python package and project manager, written in Rust.)
- [yazi](https://github.com/sxyazi/yazi) (blazingly fast and fancy TUI file manager)
- [zoxide](https://github.com/ajeetdsouza/zoxide) (cd with memory)

### 7. Neovim (Text Editor, v0.10+ or latest)

- [Lazy.nvim](https://github.com/folke/lazy.nvim) (Modern neovim package manager with lazy-loading feature)
- [Lazyvim](https://github.com/LazyVim/LazyVim) (Upstream Neovim config on top of my neovim configs)
  > Checkout the upstream LazyVim's [config](https://github.com/LazyVim/LazyVim/tree/main/lua/lazyvim/config) and
  > [plugins](https://github.com/LazyVim/LazyVim/tree/main/lua/lazyvim/plugins) and
  > [extra plugins](https://github.com/LazyVim/LazyVim/tree/main/lua/lazyvim/plugins/extras) (not installed by default) \
  > Then adjust your customisation accordingly below
- ~/.config/nvim/lua/plugins/\* (put your customisation of plugins here)
- ~/.config/nvim/lua/config/autocmds.lua (put your custom autocmd here)
- ~/.config/nvim/lua/config/keymaps.lua (put your custom keybindings here)
- ~/.config/nvim/lua/config/options.lua (custom options for your neovim)
- ~/.config/nvim/lua/config/lazy.lua (instruct neovim to load Lazyvim's plugin and your custom plugin)

### 8. [OpenCode](https://opencode.ai/docs/)

**OpenCode** is a powerful terminal-based AI coding agent that brings intelligent code assistance directly to your shell. It supports multiple AI providers (OpenAI, Claude, Gemini, Groq, Copilot, and more) and can automate coding, debugging, and file operations in your projects.

```sh
# Initial OpenCode setup
opencode auth login

# For project setup, generate AGENTS.md file
opencode
/init

# Setup skills for OpenCode
https://opencode.ai/docs/skills/#use-an-example

```

This setup installs OpenCode v2 (requires mise >= 2026.10.9; older mise versions
install v1). Terminal settings live in `~/.config/opencode/cli.json`; the legacy
`tui.json` is no longer used.

#### Claude-skills

1. [obra/superpowers](https://github.com/obra/superpowers) A framework that comes with a set of skills for software development
2. [anthropics/skills](https://github.com/anthropics/skills) Official claude skill list
3. [travisvn/awesome-claude-skills](https://github.com/travisvn/awesome-claude-skills) Community curated list of Claude skills
4. [ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills) Community curated list of Claude skills
5. [skillsmp](https://skillsmp.com/) Marketplace for Claude skills, be aware of malicious skills
6. [claude-skill-antivirus](https://github.com/claude-world/claude-skill-antivirus/tree/main) An example of claude-skill scanner for malicious skills.

#### Opencode Plugin

One plugin per layer, essentials only (reasoning in the optional notes wiki; see
`./install --wiki` under Docs below).
Add plugins by editing `opencode.json` / `opencode_work.json` here, not with
`opencode plugin add` (it rewrites the symlinked config).

1. [obra/superpowers](https://github.com/obra/superpowers) (workflow)

- User need to install this using installation prompt from the project's README
- OpenCode v2 support requires v6.4.1 or later

2. [opencode-mem](https://github.com/tickernelz/opencode-mem) (memory)

- Persistent memory using local vector search
- OpenCode v2 support requires 2.42.0 or later (`plugins` config key)

3. [cc-safety-net](https://github.com/kenryu42/cc-safety-net) (safety)

- Blocks destructive commands and reads of SSH keys / `.env` files before they run
- OpenCode v2 support requires 2.0.6 or later; needs Node.js 22+

4. [opencode-quota](https://github.com/slkiser/opencode-quota) (observability)

- `/quota` and `/quota_usage`: limits, tokens and cost for Copilot and OpenCode Go
- Requires OpenCode 2.0.26 or later and Node.js 22.13+

Context management uses V2's built-in compaction (`compaction.auto: true`), not a plugin.

#### Subagents

Global subagents live in `.config/opencode/agents/` (`cpp-reviewer`, `reviewer`, `investigator`,
`release-mapper`, `build-runner`, `scribe`, `jira`, `confluence`), next to one extra primary
agent, `coder`: plan with `build` on a strong model, then press Shift+Tab to `coder` (a cheaper
model) to implement. Authors run on Claude; `reviewer` and `cpp-reviewer` run on GPT for a second opinion.
Project know-how goes into
each repo's `.agents/skills/` so Copilot and OpenCode teammates share it. The global
`.config/opencode/AGENTS.md` holds rules for every session, including when a new skill or
subagent is worth adding. Walkthrough with diagrams: [`docs/agent-workflow.pdf`](docs/agent-workflow.pdf).

### 9. Neovim Plugins (special mentioned)

There are many plugins that I use, but here are some of the most essential ones:

- Markdown preview ([iamcco/markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim))
  > I use this to preview my markdown files, it will open a browser window
- LazyVim ([LazyVim/LazyVim](https://github.com/LazyVim/LazyVim))
  > This is the upstream neovim config, I use this as a base on top of my own neovim
  > config, due to Lua programming language, it is very easy to extend and
  > modify
- Package manager ([folke/lazy.nvim](https://github.com/folke/lazy.nvim))
  > Have a good UI to manager all the plugins for your Neovim
- Syntax highlighter ([nvim-treesitter/nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter))
  > Support many languages, the syntax highlighting is fast and accurate
- Mason ([mason-org/mason.nvim](https://github.com/mason-org/mason.nvim))
  > This is a package manager for neovim's lsp/formatters/linters/dap
- Formatter ([steverac/conform.nvim](https://github.com/stevearc/conform.nvim))
  > Formatter for many languages, it is fast and accurate
- Linter ([mfussenegger/nvim-lint](https://github.com/mfussenegger/nvim-lint))
  > Provides additional linter for many languages that is not supported by lsp
- which-key ([folke/which-key.nvim](https://github.com/folke/which-key.nvim))
  > This is a keybinding helper, it will show you the available keybindings
- Auto-completion ([saghen/blink.cmp](https://github.com/Saghen/blink.cmp))
  > This is a completion engine for neovim
- Search and replace ([MagicDuck/grug-far.nvim](https://github.com/MagicDuck/grug-far.nvim))
  > This is a search and replace tool for neovim
- Multicursor ([jake-stewart/multicursor.nvim](https://github.com/jake-stewart/multicursor.nvim))
  > This is a multi-cursor tool for neovim, to smart edit multiple lines at once
- Github Copilot ([zbirenbaum/copilot.lua](https://github.com/zbirenbaum/copilot.lua) and [CopilotC-Nvim/CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim))
  > Copilot and Copilot Chat plugins for neovim, allow you to use Copilot in
  > neovim and chat with it

### 10. Tmux (Terminal Multiplexor, v3.4+ or latest)

- ~/.config/tmux/tmux.conf (tmux configuration file)

```sh
# Create new session
tmux new -s dev
# Attach to a session
tmux attach -t dev
# Kill a session
tmux kill-session -t dev
```

## 🧰 Additional tools:

Here are some additional tools that I use in my development environment:

1. Super productivity ([super-productivity](https://github.com/johannesjo/super-productivity))

- I use this to organize my work, it is a time tracking and task management tool
- I break my work into small tasks and track my time spent on each task

## 📄 Docs

- [`docs/key-management.pdf`](docs/key-management.pdf) — key model, new-machine flow, which action
  to take, rotation, restore from backup, command reference, and GPG versus SSH.
- [`docs/agent-workflow.pdf`](docs/agent-workflow.pdf) — how the OpenCode primaries (`plan`, `build`,
  `coder`) and subagents work together, which model runs where, and the steps from an idea to a
  merged change. Rebuild with `python3 docs/src/agent-workflow.py`.
- AI-workflow notes live in a separate, private wiki repo of your own (optional). Clone it with
  `./install --wiki <git-url>` to `~/wiki/ai-workflow` (or `AI_WIKI_DIR`). If it has an
  `instructions.md`, OpenCode loads it as personal rules; `test/ai-inventory.sh` checks its
  `inventory.md` against the installed agents and skills.

## 🧪 Tests

```sh
./run ci:keys                          # keys pass, hermetic: temp HOME, generated keys, local stores
./run ci:wiki                          # wiki pass, hermetic: temp HOME, local wiki repo
bash test/install-only.sh              # ./install --only pieces, hermetic: fake commands, temp HOME
./run ci:keys:linux                    # same in Ubuntu 24.04, Ubuntu 26.04 and Arch containers
./run ci:install:linux ubuntu:26.04    # full first pass in one container, then checks the result
test/opencode-agents.sh                # local only: global OpenCode subagents load with the intended models and permissions
test/ai-inventory.sh                   # local only: agents and skills match the private wiki inventory (warns without it)
```

CI runs the keys and `./install --only` tests on Ubuntu 24.04/26.04, Arch and macOS for every push (`ci.yml`), and the full
install weekly, on demand, and when `install` changes (`install.yml`).

## 📗 Troubleshooting:

### 1. Managing multiple github accounts using SSH

- `./install --keys DIR --work-pc` sets this up for you; this is what it writes.
- `~/.config/git/config.local` is the global identity (work on a work PC):
  ```
  [user]
    name = <your_name>
    email = <your_email>
    signingkey = <primary_key_fingerprint>
  [core]
    sshCommand = "ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes"
  [commit]
    gpgsign = true
  [tag]
    gpgSign = true
  [gpg]
    program = gpg
  ```
- The global git config already includes it:
  ```
  [include]
    path = ~/.config/git/config.local
  ```
- `~/.config/git/config.local.personal` has the same shape with the personal identity and
  `~/.ssh/id_ed25519`. Personal repos opt in through `${repo}/.git/config` (or
  `git config --local --edit`):
  ```
  [include]
    path = ~/.config/git/config.local.personal
  ```
- View what a repo actually uses with `git config --list --show-origin`
- Other hosts (test benches, servers) get their own key, pinned per host in `~/.ssh/config`:
  ```
  Host bench
    HostName 192.0.2.10
    User me
    IdentityFile ~/.ssh/id_ed25519_bench
    IdentitiesOnly yes
  ```
- The key model behind this setup — one GPG primary per trust domain, a shared encryption subkey
  and a signing subkey per machine, one SSH key per machine per trust domain — is described in
  [`docs/key-management.pdf`](docs/key-management.pdf).

### 2. Git Commit Freeze Due to GPG Lock issue

- [Issue](https://gist.github.com/bahadiraraz/f2fb15b07e0fce92d8d5a86ab33469f7)

### 3. [Github API rate limit](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)

- Mise by default uses unauthenticated requests to the GitHub API (60 request/hr)
- To increase the rate limit to 5000 requests/hr, you can set the `GITHUB_TOKEN`

### 4. Having issue accessing public Github (behind corporate proxy)

- Verify if public Github reachable

```sh
ssh -T git@github.com
```

- Create ~/.ssh/confg file

```sh
touch ~/.ssh/config
```

- Paste below to config, in my case to access public Github, I need to specify Port 443 instead of 22

```sh
# Access to public github
Host github.com
User git
Hostname ssh.github.com
Identityfile ~/.ssh/id_ed25519
Port 443

Host gitlab.com
User git
Hostname altssh.gitlab.com
Identityfile ~/.ssh/id_ed25519
Port 443
```

### 5. curl: (60) SSL certificate problem: self-signed certificate in certificate chain

- This usually means you are behind a proxy
- You need to obtain the Proxy provider's CA certs

```sh
# For Ubuntu/Debian
# Place the CA / Security Certs in this path
sudo cp <path_to>/proxy_ca.crt /usr/local/share/ca-certificates
# Update the system
sudo update-ca-certificates

# For Arch
# Place the CA / Security Certs in this path
sudo cp <path_to>/proxy_ca.crt /etc/ca-certificates/trust-source/anchors
# Update the system
sudo trust extract-compat

# Test curl
curl https://example.com
```

### 6. yarn install throws 'error Error: self-signed certificate in certificate chain'

- This usually means you are behind a proxy
- You need to obtain the Proxy provider's CA certs
- You can also add this in ~/.config/zsh/.zprofile.local

```sh
# Usually at /usr/local/share/ca-certificates/
export NODE_EXTRA_CA_CERTS="<path_to>/proxy_ca.crt"
```

### 7. Wsl2 dns resolv issue, unable to ping LAN which can be ping-ed from Windows

- Open Powershell

```sh
# This will return Server and Address, copy the DNS Server's Address
nslookup google.com
```

- Open .wslconfig (usually on %USERPROFILE/.wslconfig) and paste in the address to 'dnsTunnelingIpAddress'

```sh
[experimental]
hostAddressLoopback=true
dnsTunnelingIpAddress=<DNS_Server_Address>
[wsl2]
dnsTunneling=true
networkingMode=mirrored
autoProxy=true
guiApplications=true
```

### 8. clipboard: error invoking wl-copy: Failed to connect to a Wayland server: No such file or directory Note: WAYLAND_DISPLAY is set to wayland-0 Note: XDG_RUNTIME_DIR is set to /run/user/1000/ Please check whether /run/user/1000/wayland-0 socket exists and is accessible.

- This happens when interop appendWindowsPath = true

```sh
# Check if wayland-0 exist here
# wayland-0 usually exist here for wslg
ls -la /run/user/1000/
ls -la /wslg/runtime-dir/wayland-0
# symlink it to /run/user/1000
ln -s /wslg/runtime-dir/wayland-0 /run/user/1000/wayland-0
```

- You can also make it permenant at ~/.config/zsh/.zshrc.local

```sh
if [ -e /wslg/runtime-dir/wayland-0 ]; then
  if [ ! -e /run/user/1000/wayland-0 ]; then
    ln -s /wslg/runtime-dir/wayland-0 /run/user/1000/wayland-0
  fi
fi
```

### 9. [Wsl high input lag](https://github.com/zsh-users/zsh-syntax-highlighting/issues/790)

- This is due to interop appendWindowsPath = true, which import all
  Windows path to WSL

```sh
# /etc/wsl.conf
[interop]
enabled = true
appendWindowsPath = false # set this to false
```

- Markdown preview not working due to cmd.exe not found

```sh
# Example in order to use cmd.exe which is located in /mnt/c/Windows/System32
# Manually appendWindowsPath to ~/.config/zsh/.zprofile.local
win_path="/mnt/c/Windows/System32"
if [[ ":$PATH:" != *":$win_path:"* ]]; then
  export PATH="$PATH:$win_path"
fi
```

### 10. Mount network drive in WSL (Ubuntu/Debian)

a. Method 1 - Using Drvfs (Very bad performance)

```sh
sudo mount -t drvfs D: /mnt/d
```

b. Method 2 - Using manual mount (cifs)

```sh
sudo apt update && sudo apt install -y cifs-utils nfs-kernel-server
# Create credentials file
echo "username=<username>" > ~/<cred_name>.cred
echo "password=<password>" >> ~/<cred_name>.cred
chmod 600 ~/<cred_name>.cred

mkdir -p /media/<share>
sudo mount -t cifs //<server>/<share> /media/<share> -o credentials=<path_to>/<cred_name>.cred, \
iocharset=utf8,uid=$(id -u),gid=$(id -g)
```

c. Method 3 - Using /etc/fstab (Error: processing fstab with mount -a failed)

- This happens because fstab tries to mount the network drive before the DNS server is up.

```sh
sudo apt update && sudo apt install -y cifs-utils nfs-kernel-server
mkdir -p /media/<share>
sudo -E nvim /etc/fstab
# Insert the following line
//<server>/<share> /media/<share> cifs credentials=<path_to>/<cred_name>.cred, \
iocharset=utf8,uid=1000,gid=1000 0 0
```

d. Method 4 - Using systemd

```sh
# Create systemd mount unit
sudo -E nvim /etc/systemd/system/<mount_name>.mount

# Insert the following lines
[Unit]
Description=Mount CIFS Share to /media/<share>
Requires=network-online.target
After=network-online.target

[Mount]
What=//<server>/<share>
Where=/media/<share>
Type=cifs
Options=credentials=<path_to>/<cred_name>.cred,iocharset=utf8,uid=1000,gid=1000
TimeoutSec=30

[Install]
WantedBy=multi-user.target

# Enable the mount unit (restart wsl2 after this)
sudo systemctl enable <mount_name>.mount
```

### 11. [Proxy Auto-Configuration (PAC) issue](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting#considerations-when-using-autoproxy-for-httpproxy-mirroring-in-wsl)

- If you enable mirrored networkingMode and autoProxy, WSL2 will import proxy settings from Windows
- If you are then also behind corporate proxy which employ PAC, when the VPN auto renew proxy settings, \
  WSL2 will not be able to access the internet which probably caused by "WSL_PAC_URL" become unset
  > .wslconfig

```sh
[experimental]
hostAddressLoopback=true
dnsTunnelingIpAddress="<DNS_Server_Address>"
[wsl2]
dnsTunneling=true
networkingMode=mirrored
autoProxy=true
guiApplications=true
```

> Add the following into ~/.config/zsh/.zshrc.local

```sh
# If WSL_PAC_URL is not set, set it to the default PAC URL
if [[ -z "${WSL_PAC_URL}" ]]; then
  export WSL_PAC_URL=<corporate_pac_url>
fi
```

- Restart WSL2 or Restart PC if it doesn't work

```sh
wsl --shutdown
```

### 12. [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: self-signed certificate in certificate chain (\_ssl.c:1028)

- Problem with some python packages not trusting the corporate proxy self-signed cert

```sh
# Append this in ~/.config/zsh/.zprofile.local
# Usually at /usr/local/share/ca-certificates/
export SSL_CERT_FILE=<path_to>/<proxy.crt
```

### 13. WezTerm on Windows must be nightly

The last stable release (20240203) has two problems that nightly fixes:

- Images do not display, because it bundles an outdated ConPTY.
- A tmux pane on the right side that scrolls also corrupts the pane on its
  left: from column N on (N = number of terminal rows), the left pane
  scrolls with it. Stable clamps the DECSLRM left margin by rows instead of
  columns ([wezterm#5871](https://github.com/wezterm/wezterm/pull/5871)).

To switch an existing stable install or update nightly, run
`./install --only wezterm` (pieces: `zsh`, `wezterm`, `tmux`, `health`). The
installer needs admin rights and closes all WezTerm windows, so on WSL close
WezTerm first and run it from PowerShell:

```powershell
wsl.exe -e bash -lc '~/dotfiles/install --only wezterm'
```

### 14. WSL starts with root instead of user

```sh
# Run this in wsl
wsl.exe --manage <distro_name> --set-default-user <username_in_distro>
```

### 15. uv TLS issue when (uv pip sync requirement.txt)

Your system CA store is correct (as shown by `openssl`), but `uv` is still failing with `invalid peer certificate: UnknownIssuer`. This usually means:

- `uv` (via `rustls-tls-native-roots`) is not picking up your system CA store as expected.
- There may be a conflict with custom CA environment variables.
- You are behind a corporate proxy that intercepts SSL, and its CA is not trusted by the system or not compatible with `rustls`.

**Unset Python/Node CA environment variables**
These can interfere with native TLS detection:

```sh
unset SSL_CERT_FILE
unset REQUESTS_CA_BUNDLE
unset NODE_EXTRA_CA_CERTS
```

### 16. How to build custom kernel for wsl2

[Nice youtube guide and still relevant in 2025](https://www.youtube.com/watch?v=t_YnACEPmrM)

### 17. How to renew a GPG key (before it expires)

GPG keys do **not** auto-renew. Once a subkey expires, commits stop signing and new store entries
stop encrypting. Renewing is a new self-signature: the fingerprint, git config and store recipients
all stay the same. The primary key is offline (`gpg -K` shows `sec#`), so bring it back for the
renewal on **one** machine, then let the other machines pick up the public block.

```sh
# 1. Expiry dates and the fingerprint
gpg --list-secret-keys --keyid-format=long
FPR=<40-hex primary fingerprint>

# 2. Bring the primary back. Import the latest public block too, so the
#    other machines' signing subkeys get renewed as well.
gpg --import ~/key-backup/personal-primary.asc ~/key-backup/personal-public.asc

# 3. Extend the primary, then every subkey
gpg --quick-set-expire "$FPR" 3y
gpg --quick-set-expire "$FPR" 2y '*'

# 4. Remove the primary's secret again ("!" = the primary alone); expect sec#
gpg --batch --yes --delete-secret-keys "$FPR!"
gpg -K "$FPR"

# 5. Publish: the expiry lives in the public block
gpg --armor --export "$FPR" > ~/key-backup/personal-public.asc
#    then on GitHub: gh gpg-key delete <last 16 hex of $FPR> --yes
#                    gh gpg-key add ~/key-backup/personal-public.asc --title personal

# 6. On every other machine
gpg --import ~/key-backup/personal-public.asc
```

Same steps with `work-*` files for the work identity. Copy the updated `*-public.asc` back to the
offline backup. Full procedure and rotation: [`docs/key-management.pdf`](docs/key-management.pdf).

### 18. apt fails with `401 Server authentication required` behind corporate proxy (curl works)

- Symptom: `curl -v --proxy $http_proxy https://<example-apt-repo>/dists/*/InRelease` returns
  `200 Connection established`, but `sudo apt update` fails with:
  `401 Server authentication required [IP: <transparent-proxy-ip> <port>]`
- Cause: `sudo` strips env, so apt never sees `$http_proxy`. It falls back to the
  transparent (intercepting) proxy (`<transparent-proxy-ip>:<port>` = `<transparent-proxy-host>`)
  without auth, while curl uses the explicit (authenticated forward) proxy
  `<explicit-proxy-host>:<port>` (`<explicit-proxy-ip>`) with Basic auth.
- Find hostnames:

```sh
getent hosts <transparent-proxy-ip>
getent hosts <explicit-proxy-host>
```

- Fix: point apt at the explicit proxy (no creds in world-readable file):

```sh
sudo tee /etc/apt/apt.conf.d/99proxy >/dev/null <<EOF
Acquire::http::Proxy "http://<explicit-proxy-host>:<port>/";
Acquire::https::Proxy "http://<explicit-proxy-host>:<port>/";
EOF
```

- Notes: `export http_proxy="http://USER:PASS@HOST:PORT"` format still applies to curl/shell,
  but `sudo apt` needs the files above. Truly passwordless only works with a local
  NTLM/Kerberos forwarder (e.g. `px`) listening on `127.0.0.1:3128`.

## 👑 Credits:

1. [Nick Janetakis](https://github.com/nickjj/dotfiles)

- Big thanks to Nick for his dotfiles project. I learned a lot from it and
  used it as a base for my own dotfiles.
