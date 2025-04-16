-- Global variables.
MAP = vim.keymap.set
DEL = vim.keymap.del

-- Bootstrap lazy.nvim, LazyVim and your plugins.
require("config.keymaps")
require("config.autocmds")
require("config.options")
require("config.lazy")
