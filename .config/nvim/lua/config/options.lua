-- Options are automatically loaded before lazy.nvim startup.
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

-- The ~/.local/state/nvim/lsp.log can get pretty noisy. Mine was ~28MB after 2
-- weeks with the default setting. My thought process here is it can remain OFF
-- by default but if you're looking to troubleshoot something you can
-- temporarily set this to WARN or ERROR.
vim.lsp.set_log_level("OFF")

vim.cmd("let g:netrw_liststyle = 3")

local opt = vim.opt

-- tabs & indentation
opt.tabstop = 2 -- 2 spaces for tabs (prettier default)
opt.shiftwidth = 2 -- 2 spaces for indent width
opt.expandtab = true -- expand tab to spaces
opt.autoindent = true -- copy indent from current line when starting new one

-- search settings
opt.ignorecase = true -- ignore case when searching
opt.smartcase = true -- if you include mixed case in your search, assumes you want case-sensitive

opt.cursorline = true

-- turn on termguicolors for tokyonight colorscheme to work
-- (have to use iterm2 or any other true color terminal)
--opt.termguicolors = true
--opt.background = "dark" -- colorschemes that can be light or dark will be made dark
opt.signcolumn = "yes" -- show sign column so that text doesn't shift

-- backspace
opt.backspace = "indent,eol,start" -- allow backspace on indent, end of line or insert mode start position

-- clipboard
opt.clipboard = vim.env.SSH_TTY and "" or "unnamedplus" -- Sync with system clipboard

-- split windows
opt.splitright = true -- split vertical window to the right
opt.splitbelow = true -- split horizontal window to the bottom



opt.relativenumber = true
opt.number = true

-- I prefer seeing all characters by default.
opt.conceallevel = 0

-- Show a vertical line at this character.
opt.colorcolumn = "80"

-- Each buffer gets its own status line instead of sharing one.
opt.laststatus = 2

-- These are all invisible by default but we can toggle them with a keymap.
opt.listchars = {
  eol = "$",
  tab = ">-",
  trail = "-",
  lead = "-",
  extends = "~",
  precedes = "~",
  conceal = "+",
  nbsp = "&",
}
opt.list = false

-- Don't auto-scroll N number of lines from the top of the buffer.
opt.scrolloff = 0

-- Allow left and right arrow keys to move to the previous and next line.
opt.whichwrap = "b,s,<,>"

-- Wrap lines so it's easier to see anything that's cut off.
opt.wrap = true

