local data_path = vim.fn.stdpath("config") .. "/lua/plugins/data"
local markdownlint_cli2_path = data_path .. "/.markdownlint-cli2.yaml"
local markdown_preview_css_path = data_path .. "/github-markdown.css"

return {
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		ft = { "markdown" },
		build = "cd app && yarn install",
		init = function()
			vim.g.mkdp_auto_close = false
			vim.g.mkdp_markdown_css = markdown_preview_css_path
		end,
		config = function()
			-- Define custom browser function
			vim.cmd([[
				function! OpenMarkdownPreview(url)
					if has('win32')
						lua vim.notify("Opening mdp with Windows cmd.exe", vim.log.levels.INFO)
						silent execute '!start /b cmd.exe /c start "" "' . a:url . '"'
					elseif has('wsl')
						lua vim.notify("Opening mdp with explorer.exe", vim.log.levels.INFO)
						silent execute '!explorer.exe ' . shellescape(a:url)
					else
						lua vim.notify("Opening mdp with xdg-open", vim.log.levels.INFO)
						silent execute '!xdg-open ' . a:url
					endif
				endfunction
    ]])
			vim.g.mkdp_browserfunc = "OpenMarkdownPreview"
			vim.g.mkdp_filetypes = { "markdown" }
		end,
	},
	{
		"stevearc/conform.nvim",
		opts = {
			formatters = {
				["markdownlint-cli2"] = {

					args = { "--config", markdownlint_cli2_path, "--fix", "$FILENAME" },
				},
			},
		},
	},
	{
		"mfussenegger/nvim-lint",
		opts = {
			linters = {
				["markdownlint-cli2"] = {
					args = { "--config", markdownlint_cli2_path, "--" },
				},
			},
		},
	},
	{
		"MeanderingProgrammer/render-markdown.nvim",
		opts = {
			enabled = false,
			win_options = {
				colorcolumn = { default = vim.o.colorcolumn, rendered = "" },
			},
			heading = {
				width = "block",
				min_width = tonumber(vim.o.colorcolumn),
			},
		},
	},
}
