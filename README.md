# dotfiles

## 📓Supported platforms
- Archlinux
- Ubuntu 22+
- macOS (not yet tested)
- wsl2 (Archlinux/ Ubuntu22+)

## 🔗 Requirements
- git
- curl
- bash 4+
- [Docker](https://docs.docker.com/engine/install/) (for experience it or local test)

## 🔨 Installation
### Local way
```sh
git clone https://github.com/otakenz/dotfiles.git
cd ~/dotfiles
LOCAL=1 bash install
```

### One-liner way
```sh
bash <(curl -sS https://raw.githubusercontent.com/otakenz/dotfiles/master/install)
```

### (Optional) Change remote url to ssh
```sh
git remote set-url origin git@github.com:otakenz/dotfiles.git
```

## Install script
This script is designed to be run on a fresh install of the supported platforms. It will install the following:
### 1. [wezterm](https://wezterm.org/index.html) (cross platform GPU accelerated terminal)
- New Wezterm application installed on your desktop
- Config wezterm at ~/.config/wezterm/wezterm.lua
- [Windows] You have to install wezterm installer for Windows manually
- Config wezterm for windows is copied to %USERPROFILE%/.wezterm.lua
### 2. [Powerlevel10k](https://github.com/romkatv/powerlevel10k) (Terminal theme)
- p10k configure (when needed to reconfigure)
- ~/.config/zsh/.p10k.zsh (config stored here)
### 3. [Meslo Nerd Font](https://www.nerdfonts.com/font-downloads) (Terminal Fonts that support icons)
- Fonts data installed at ~/.local/share/fonts/
- fc-cache -fv (load new fonts to terminal)
- [Window] You have to install Nerd Fonts manually
- Unzip the installed NerdFonts to %USERPROFILE%/.local/share/fonts
- Choose the fonts style and click "install"
### 4. zsh (Z shell - modern shell)
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
- node@22.14, python@3.13, go@1.23, lua@5.4, rust@1.86
### 6. Tools (special mentioned)
- [bat](https://github.com/sharkdp/bat) (better cat, provide colors)
- [delta](https://github.com/dandavison/delta) (provide syntax highlighting for git, diff)
- [eza](https://github.com/eza-community/eza) (better ls, with color and icons)
- [fd](https://github.com/sharkdp/fd) (find on steroids, ultra fast files search)
- [fzf](https://github.com/junegunn/fzf) (fuzzy finder)
- [gitui](https://github.com/gitui-org/gitui) (git TUI, written in rust, can be spawned inside neovim)
- [lazygit](https://github.com/jesseduffield/lazygit) (another git TUI, written in go, can be spawned inside neovim)
- [ripgrep](https://github.com/BurntSushi/ripgrep) (ultra fast regex search on files)
- [tldr](https://github.com/tldr-pages/tldr) (cheatsheet for console commands)
- [zoxide](https://github.com/ajeetdsouza/zoxide) (cd with memory)
### 7. Neovim (v0.10+ or latest)
- [Lazy.nvim](https://github.com/folke/lazy.nvim) (Modern neovim package manager with lazy-loading feature)
- [Lazyvim](https://github.com/LazyVim/LazyVim) (Upstream Neovim config on top of my neovim configs)
> Checkout the upstream LazyVim's [config](https://github.com/LazyVim/LazyVim/tree/main/lua/lazyvim/config) and 
 [plugins](https://github.com/LazyVim/LazyVim/tree/main/lua/lazyvim/plugins) and
 [extra plugins](https://github.com/LazyVim/LazyVim/tree/main/lua/lazyvim/plugins/extras) (not installed by default) \
 Then adjust your customisation accordingly below
- ~/.config/nvim/lua/plugins/* (put your customisation of plugins here)
- ~/.config/nvim/lua/config/autocmds.lua (put your custom autocmd here)
- ~/.config/nvim/lua/config/keymaps.lua (put your custom keybindings here)
- ~/.config/nvim/lua/config/options.lua (custom options for your neovim)
- ~/.config/nvim/lua/config/lazy.lua (instruct neovim to load Lazyvim's plugin and your custom plugin)
#### Plugins (special mentioned)
-
### 8. Tmux (v3.4+ or latest)
- ~/.config/tmux/tmux.conf (tmux configuration file)
```sh
# Create new session
tmux new -s dev
# Attach to a session
tmux attach -t dev
# Kill a session
tmux kill-session -t dev
```

## Experience it
**Try it in Docker without modifying your system:**

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
### 8. clipboard: error invoking wl-copy: Failed to connect to a Wayland server: No such file or directory Note: WAYLAND_DISPLAY is set to wayland-0 Note: XDG_RUNTIME_DIR is set to /run/user/1000/ Please check whether /run/user/1000//wayland-0 socket exists and is accessible. 
```sh
# Check if wayland-0 exist here
ls -la /run/user/1000/
# wayland-0 usually exist here for wslg
ls -la /wslg/runtime-dir/wayland-0
# symlink it to /run/user/1000
ln -s /wslg/runtime-dir/wayland-0 /run/user/1000/wayland-0
```

## 👑 Credits:

1. [Nick Janetakis](https://github.com/nickjj/dotfiles)

- Big thanks to Nick for his dotfiles project. I learned a lot from it and
  used it as a base for my own dotfiles.
