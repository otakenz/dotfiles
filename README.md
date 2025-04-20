Mise by default uses unauthenticated requests to the GitHub API (60 request/hr)
To increase the rate limit to 5000 requests/hr, you can set the `GITHUB_TOKEN`
Generate one from here https://github.com/settings/tokens

**Try it in Docker without modifying your system:**

```sh
# Start a Debian container, we're passing in an env var to be explicit we're in Docker.
docker container run --rm -it -e "IN_CONTAINER=1" -v "${PWD}:/app" -w /app debian:stable-slim bash

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

docker container run --rm -it -e "IN_CONTAINER=1" -v "${PWD}:/app" -w /app debian:stable-slim bash

# Local test only
apt-get update && apt-get install -y curl \
  && bash /app/install \
  && zsh -c ". ~/.config/zsh/.zprofile && . ~/.config/zsh/.zshrc; zsh -i"
```

_Keep in mind with the Docker set up, unless your terminal is already
configured to use Tokyonight Moon then the colors may look off. That's because
your local terminal's config will not get automatically updated._

## 👑 Credits:

1. [Nick Janetakis](https://github.com/nickj/dotfiles)

- Big thanks to Nick for his dotfiles project. I learned a lot from it and
  used it as a base for my own dotfiles.
