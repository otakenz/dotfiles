Dependencies:
- git
- curl

Install Wezterm
https://wezterm.org/installation.html

Install this script
- sudo apt-get update && sudo apt-get install -y curl \
  && bash <(curl -sS https://raw.githubusercontent.com/otakenz/dotfiles/master/install) 
  - If you install this way, and later wants to push to github using ssh key, you have to edit your local git config
  - git config --local --config
  - under [remote "origin"] edit "url", https:// -> git@ and .com/ -> .com:

- sudo apt-get update && sudo apt-get install -y curl \
  && LOCAL=1 bash ~/dotfiles/install

Install Powerlevel10k (Terminal Theme)

- https://github.com/romkatv/powerlevel10k
- git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
- source ~/.zshrc
  Reconfigure
  - p10k configure

Install Nerf Fonts (https://www.nerdfonts.com/)

- use Meslo Nerd Font
  Ubuntu
  Download Meslo Nerd Font
- mkdir -p ~/.local/share/fonts
- cd ~/.local/share/fonts
- wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/Meslo.zip
- unzip Meslo.zip
- rm Meslo.zip
  Refresh font cache (make system aware of the new fonts)
- fc-cache -fv

- <https://www.nerdfonts.com/font-downloads>
- I use MesloLGS Nerd Font Mono

Bat
bat cache --build
bat --list-themes | grep tokyo # should output "tokyonight_night"
echo '--theme="tokyonight_night"' >> "$(bat --config-dir)/config"


Mise by default uses unauthenticated requests to the GitHub API (60 request/hr)
To increase the rate limit to 5000 requests/hr, you can set the `GITHUB_TOKEN`
Generate one from here https://github.com/settings/tokens

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

**  Local Test**

```sh
cd dotfiles/

docker container run --rm -it --env-file .env -e "IN_CONTAINER=1" -v "${PWD}:/app" -w /app debian:stable-slim bash

# Local test only
apt-get update && apt-get install -y curl \
  && LOCAL=1 bash install \
  && zsh -c ". ~/.config/zsh/.zprofile && . ~/.config/zsh/.zshrc; zsh -i"
```

_Keep in mind with the Docker set up, unless your terminal is already
configured to use Tokyonight Moon then the colors may look off. That's because
your local terminal's config will not get automatically updated._

## 📗 FAQ:
1. Managing multiple github accounts using SSH
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


## 👑 Credits:

1. [Nick Janetakis](https://github.com/nickjj/dotfiles)

- Big thanks to Nick for his dotfiles project. I learned a lot from it and
  used it as a base for my own dotfiles.
