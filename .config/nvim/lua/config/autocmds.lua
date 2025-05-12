-- Autocmds are automatically loaded on the VeryLazy event.
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

local cursorline_group =
	vim.api.nvim_create_augroup("cursorline", { clear = true })
vim.api.nvim_create_autocmd({ "VimEnter", "WinEnter", "BufWinEnter" }, {
	group = cursorline_group,
	callback = function()
		vim.opt_local.cursorline = true
	end,
})
vim.api.nvim_create_autocmd("WinLeave", {
	group = cursorline_group,
	callback = function()
		vim.opt_local.cursorline = false
	end,
})

-- Fix indentation if a . comes before end such as when using "self.".
-- Source: https://github.com/tree-sitter/tree-sitter-ruby/issues/230
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "ruby" },
	callback = function()
		vim.opt_local.indentkeys:remove(".")
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "make" },
	callback = function()
		vim.opt_local.expandtab = false
		vim.opt_local.shiftwidth = 4
	end,
})

vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
	pattern = { "*.yaml", "*.yml" },
	callback = function()
		if
			vim.fn.getline(1):match("^apiVersion:")
			or vim.fn.getline(2):match("^apiVersion:")
		then
			vim.opt_local.filetype = "helm"
		end
	end,
})

-- Force these files to be markdown type
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = { "LICENSE", "LICENSE.*", "README", "README.*" },
	callback = function()
		vim.bo.filetype = "markdown"
	end,
})

-- Retrigger filetype detection on write if the filetype is empty or text
vim.api.nvim_create_autocmd("BufWritePost", {
	pattern = "*",
	callback = function()
		if vim.bo.filetype == "" or vim.bo.filetype == "text" then
			vim.cmd("filetype detect")
		end
	end,
})

-- Customize highlighting for C and C++ comments with LSP semantic tokens.
-- This is particularly useful for handling preprocessor directives (`#define`, `#ifdef`, etc.)
-- in both C and C++ files, where we ensure that the background color of comments is distinct
-- while preserving the foreground and italic styles based on the LSP configuration.
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "cpp", "c" },
	callback = function()
		local comment_hl = vim.api.nvim_get_hl(
			0,
			{ name = "@lsp.type.comment.cpp", link = true }
		) or {}
		local new_bg = "#444a73"

		-- List of LSP semantic token types to update
		local comment_types = { "@lsp.type.comment.cpp", "@lsp.type.comment.c" }

		-- Apply the highlight for both C and C++ comments
		for _, comment_type in ipairs(comment_types) do
			vim.api.nvim_set_hl(0, comment_type, {
				fg = comment_hl.fg,
				italic = comment_hl.italic,
				bg = new_bg,
			})
		end
	end,
})

-- Restore cursor position when opening a file
-- https://github.com/neovim/neovim/issues/16339#issuecomment-1457394370
vim.api.nvim_create_autocmd("BufRead", {
	callback = function(opts)
		vim.api.nvim_create_autocmd("BufWinEnter", {
			once = true,
			buffer = opts.buf,
			callback = function()
				local ft = vim.bo[opts.buf].filetype
				local last_known_line = vim.api.nvim_buf_get_mark(opts.buf, '"')[1]
				if
					not (ft:match("commit") and ft:match("rebase"))
					and last_known_line > 1
					and last_known_line <= vim.api.nvim_buf_line_count(opts.buf)
				then
					vim.api.nvim_feedkeys([[g`"]], "nx", false)
				end
			end,
		})
	end,
})
