-- Global variables.
MAP = vim.keymap.set
DEL = vim.keymap.del

-- Bootstrap lazy.nvim, LazyVim and your plugins.
require("config.lazy")

-- Load additional configs only when UI is ready
vim.api.nvim_create_autocmd("UIEnter", {
	once = true,
	callback = function()
		require("config.editorconfig")
	end,
})
