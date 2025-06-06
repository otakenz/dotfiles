# dotfiles

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

- New Wezterm application installed on your desktop
- Config wezterm at ~/.config/wezterm/wezterm.lua

#### [Windows/WSL2]

- New Wezterm application installed on C:\Program Files\WezTerm with winget
- Config wezterm for windows is copied to %USERPROFILE%/.wezterm.lua.
  > Refer [ordering to this](https://wezterm.org/config/files.html)
- [(Manual Fixed) Known issue](#13-unable-to-display-image-in-wezterm-windows-version) that image preview not working in Window's Wezterm
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

- node@22.14, python@3.13, go@1.24, lua@5.4, rust@stable

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
- [yazi](https://github.com/sxyazi/yazi) (blazingly fast and fancy TUI file manager)
- [zoxide](https://github.com/ajeetdsouza/zoxide) (cd with memory)

### 7. Neovim (Text Editor, v0.10+ or latest)

- [Lazy.nvim](https://github.com/folke/lazy.nvim) (Modern neovim package manager with lazy-loading feature)
- [Lazyvim](https://github.com/LazyVim/LazyVim) (Upstream Neovim config on top of my neovim configs)
  > Checkout the upstream LazyVim's [config](https://github.com/LazyVim/LazyVim/tree/main/lua/lazyvim/config) and
  > [plugins](https://github.com/LazyVim/LazyVim/tree/main/lua/lazyvim/plugins) and
  > [extra plugins](https://github.com/LazyVim/LazyVim/tree/main/lua/lazyvim/plugins/extras) (not installed by default) \
  >  Then adjust your customisation accordingly below
- ~/.config/nvim/lua/plugins/\* (put your customisation of plugins here)
- ~/.config/nvim/lua/config/autocmds.lua (put your custom autocmd here)
- ~/.config/nvim/lua/config/keymaps.lua (put your custom keybindings here)
- ~/.config/nvim/lua/config/options.lua (custom options for your neovim)
- ~/.config/nvim/lua/config/lazy.lua (instruct neovim to load Lazyvim's plugin and your custom plugin)

#### Neovim Plugins (special mentioned)

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
- Mason ([williamboman/mason.nvim](https://github.com/mason-org/mason.nvim))
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

### 8. Tmux (Terminal Multiplexor, v3.4+ or latest)

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

## 📗 Troubleshooting:

### 1. Managing multiple github accounts using SSH

- Create multiple git config files (i.e config.local, config.local.personal..)
- Example of config.local:
  ```
  [user]
    name = <your_name>
    email = <your_email>
    signingkey = <your_gpg_key>"
  [core]
    sshCommand = "ssh -i ~/.ssh/<your_ssh_key> -o IdentitiesOnly=yes"
  [commit]
    gpgsign = true
  [tag]
    gpgsign = true
  [gpg]
    program = gpg
  ```
- Place it anywhere you want, i.e ~/.config/git/config.local
- config.local is going to be my global git config for work
- This script already included ~/.config/git/config in global git config like so
  ```
  [include]
    path = ~/.config/git/config.local
  ```
- For personal git config, specify the following in your ${repo}/.git/config or run "git config --local --edit"
  ```
  [include]
    path = ~/.config/git/config.local.personal
  ```
- You can view the config loaded at work repo vs personal repo by running
  ```
  git config --list
  ```

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
# Example in order to use cmd.exe which is located in /c/Windows/System32
# Manually appendWindowsPath to ~/.config/zsh/.zprofile.local
win_path="/c/Windows/System32"
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

### 13. Unable to display image in WezTerm Window's version

- This is due to the outdated ConPTY delivered in earlier version of WezTerm
  > As of May2025 latest release is that of Feb2024, but it is still outdated
- **window admin privilege required** To fix this we need to replace the conpty.dll and OpenConsole.exe in the WezTerm installation folder, with the one in ~/dotfiles/c/Program Files/WezTerm/\*.
  > Typically located at C:\Program Files\WezTerm

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

## 👑 Credits:

1. [Nick Janetakis](https://github.com/nickjj/dotfiles)

- Big thanks to Nick for his dotfiles project. I learned a lot from it and
  used it as a base for my own dotfiles.
