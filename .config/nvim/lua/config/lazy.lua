-- Define the path where lazy.nvim should be installed (inside Neovim's data directory)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

-- Check if the lazy.nvim directory exists; if not, proceed to install it
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", -- latest stable release
		lazypath,
	})
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end

-- Prepend lazy.nvim to Neovim's runtime path so it can be loaded
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	spec = {
		-- Add LazyVim and import its plugins.
		{ "LazyVim/LazyVim", import = "lazyvim.plugins" },
		-- Import or override with your plugins.
		{ import = "plugins" },
	},
	defaults = {
		-- By default, only LazyVim plugins will be lazy-loaded. Your custom
		-- plugins will load during startup. If you know what you're doing, you can
		-- set this to `true` to have all your custom plugins lazy-loaded by
		-- default.
		lazy = false,
		-- It's recommended to leave version=false for now, since a lot the plugin
		-- that support versioning, have outdated releases, which may break your
		-- Neovim install.
		version = false, -- Always use the latest git commit.
		-- version = "*", -- Try installing the latest stable version for plugins that support semver.
	},
	install = { colorscheme = { "tokyonight" } },
	checker = {
		enabled = true, -- Check for plugin updates periodically.
		notify = false, -- Notify on update.
	}, -- Automatically check for plugin updates.
	change_detection = {
		notify = false,
	},
	performance = {
		rtp = {
			-- Disable some rtp plugins.
			disabled_plugins = {
				"gzip",
				-- "matchit",
				-- "matchparen",
				-- "netrwPlugin",
				"tarPlugin",
				"tohtml",
				"tutor",
				"zipPlugin",
			},
		},
	},
})
