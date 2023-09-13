# dotfiles

## Requirements

- Vim 8.1+
- Tmux 3.0+ (compile from source if not available on apt)
- Nvim (latest/any)
- Ubuntu 20.04+
- [PowerToys](https://github.com/microsoft/PowerToys) For Windows, to swap esc and caps key bind

---

### Ubuntu 20.04+

```sh
# Run this if using vim, and do not have vim 8.1+
sudo add-apt-repository ppa:jonathonf/vim
# Run this if using neovim, unstable for latest feature
sudo add-apt-repository ppa:neovim-ppa/unstable
```

---

#### Install dependencies

```sh
sudo apt-get update && sudo apt-get install -y \
  curl \
  git \
  gnupg \
  htop \
  jq \
  pass \
  pwgen \
  python3-pip \
  ripgrep \
  rsync \
  shellcheck \
  tmux \
  unzip \
  vim-gtk \
  zsh \
  neovim

# if wsl2
  xdg-utils
```

> :information_source: If use zsh, follow [this](https://github.com/ohmyzsh/ohmyzsh/wiki/Installing-ZSH) to setup

---

#### For Work

> :office: Ensure you have access to public github (add this to ~/.ssh/config)

```
# Access to public github
Host github.com
User git
Hostname ssh.github.com
Identityfile ~/.ssh/id_ed25519_pers.pub
Port 443

Host gitlab.com
User git
Hostname altssh.gitlab.com
Identityfile ~/.ssh/id_ed25519_pers.pub
Port 443
```

---

#### Symlink the configs

> :warning: ln -fs does force symlink (overwrite), ensure affected files are backup

```sh
# Clone the dotfiles
git clone https://github.com/otakenz/dotfiles ~/dotfiles

# Create zsh directories
mkdir -p ~/.config/zsh
mkdir -p ~/.cache/zsh
# Install zsh plugins
~/dotfiles/.local/bin/update-zsh-plugins

# NOTE: The last one is WSL 1 / 2 specific. Don't do it on native Linux / macOS.
mkdir -p ~/.local/bin && mkdir -p ~/.vim/spell \
  && ln -fs ~/dotfiles/.config/zsh/.zshrc ~/.config/zsh/.zshrc \
  && ln -fs ~/dotfiles/.config/zsh/.zprofile ~/.config/zsh/.zprofile \
  && ln -fs ~/dotfiles/.config/zsh/.aliases ~/.config/zsh/.aliases \
  && ln -fs ~/dotfiles/.zshenv ~/.zshenv \
  && ln -fs ~/dotfiles/.bashrc ~/.bashrc \
  && ln -fs ~/dotfiles/.vim/coc-settings.json ~/.vim/coc-settings.json \
  && ln -fs ~/dotfiles/.vim/coc-settings.json ~/.config/nvim/coc-settings.json \
  && ln -fs ~/dotfiles/.config/nvim/init.vim ~/.config/nvim/init.vim \
  && ln -fs ~/dotfiles/.config/nvim/nvim.vim ~/.vim/nvim.vim \
  && ln -fs ~/dotfiles/.vim/work.vim ~/.vim/work.vim \
  && ln -fs ~/dotfiles/.vim/after/plugin/treesitter.lua ~/.vim/after/plugin/treesitter.lua \
  && ln -fs ~/dotfiles/.gemrc ~/.gemrc \
  && ln -fs ~/dotfiles/.gitconfig ~/.gitconfig \
  && ln -fs ~/dotfiles/.profile ~/.profile \
  && ln -fs ~/dotfiles/.tmux.conf ~/.tmux.conf \
  && ln -fs ~/dotfiles/.vimrc ~/.vimrc \
  && ln -fs ~/dotfiles/.vim/spell/en.utf-8.add ~/.vim/spell/en.utf-8.add \
  && ln -fs ~/dotfiles/.local/bin/set-theme ~/.local/bin/set-theme \
  && sudo ln -fs ~/dotfiles/etc/wsl.conf /etc/wsl.conf

# Edit this field to your name and email
cp ~/dotfiles/.gitconfig.user ~/.gitconfig.user

# Install Plug (Vim plugin manager, vim-style).
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# Install TPM (Tmux plugin manager).
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Install FZF (fuzzy finder on the terminal and used by a Vim plugin).
rm -rf "${HOME}/.local/share/fzf"
git clone --depth 1 https://github.com/junegunn/fzf.git "${HOME}/.local/share/fzf" \
  && yes | "${HOME}/.local/share/fzf/install" --bin --no-update-rc
# Manual install if not done
cd ~/.local/share/fzf/ && ./install

# Install ASDF version manager.
git clone https://github.com/asdf-vm/asdf.git ~/.local/share/asdf

# Markdown Preview that requires Node and Yarn.
# Coc need some of the latest LTS nodejs to work seamlessly
# Copilot need node
asdf plugin add nodejs
asdf install nodejs 18.17.0
asdf global nodejs 18.17.0

# Install Yarn.
npm install --global yarn

# If self-signed certificate warning when doing "yarn install"
yarn config set "strict-ssl" false

# More dependencies
sudo apt-get install -y autoconf bison build-essential libssl-dev libyaml-dev \
  libreadline6-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm6 libgdbm-dev libdb-dev

# Install python (opt)
asdf plugin add python
asdf install python 3.10.13
asdf global python 3.10.13

# For python linter (coc-pyright)
python -m pip install autopep8

```

---

#### Install plugins for Vim and tmux

```sh
# Install vim plugin
vim .
:PlugInstall

# Install tmux plugin
tmux
`I
```

---

#### Further reads on some popular vim/nvim plugins

> :school: [Learn more about coc.nvim LSP for neovim/vim](https://github.com/neoclide/coc.nvim/wiki/Language-servers#ccobjective-c) \
> :school: [Learn more about treesitter.nvim for neovim](https://github.com/nvim-treesitter/nvim-treesitter)

---

#### Config files

- coc-settings.json (coc.nvim config files)
- treesitter.lua (treesitter.nvim config files)
- vimrc (vim config file)
- init.vim (nvim config file, it source vimrc as nvim and vim is mostly compatible)
- bashrc (bash terminal config file)
- zshrc (zsh terminal config file)
- gitconfig.user (git user profile)
- gitconfig (git global config)
- tmux.conf (tmux conf)

---

#### Install and setup for Flutter development

```sh
# Install flutter
asdf plugin add flutter
asdf install flutter 3.13.3
asdf global python 3.13.3

# Flutter doctor
flutter doctor

# Install android studio (https://developer.android.com/studio)
1. Download binary
curl -OL https://redirector.gvt1.com/edgedl/android/studio/ide-zips/2022.3.1.19/android-studio-2022.3.1.19-linux.tar.gz

2. Extract to a path
tar xvf android-studio-2022.3.1.19-linux.tar.gz -C ~/Programs

3. Install some 32bits binary lib dependencies
sudo dpkg --add-architecture i386
sudo apt-get install libc6:i386 libncurses5:i386 libstdc++6:i386 lib32z1 libbz2-1.0:i386

4. Install Android studio
~/Programs/android-studio/bin/studio.sh

5. Install cmdline-tool
https://stackoverflow.com/a/71036049

6. Install Google chrome on WSL2

7. Flutter doctor until it is all green

# Connect android device from Windows to WSL2
# https://stackoverflow.com/questions/60166965/adb-device-list-empty-using-wsl2
Both Windows and Androids needs to have android studio installed
```

---

#### Optionally confirm that a few things work after closing and re-opening your terminal

```sh
# Sanity check to see if you can run some of the tools we installed.
node --version

# Check to make sure git is configured with your name, email and custom settings.
git config --list

# If you're using Docker Desktop with WSL 2, these should be accessible too.
docker info
docker-compose --version
```

---

### References

[nickjanetakis blog](https://nickjanetakis.com/blog/the-tools-i-use) list of tools I reference

---

### FAQ

#### 1. Vim takes a long time to open when inside of WSL?

> It primarily comes down to either VcXsrv not running or a firewall tool
> blocking access to VcXsrv and it takes a bit of time for the connection to time
> out.
>
> You can verify this by starting Vim with `vim -X` instead of `vim`. This
> will prevent Vim from connecting to an X server. This also means clipboard
> sharing to your system clipboard won't work, but it's good for a test.
>
> Vim will try to connect to that X server by default because `DISPLAY` is
> exported in the `.bashrc` file. Installing and configuring VcXsrv as per these
> dotfiles will fix that issue.
>
> If it still persists, it might be a software firewall issue. You can open TCP
> port 6000 and also restrict access to it from only WSL 2. This will depend on
> which tool you're using to configure that but that should do the trick.
