local M = {
	mason_tools = {
		-- Shell
		"bash-language-server", -- language server
		"shellcheck", -- linter
		"shfmt", -- formatter

		-- Clang
		"clangd", -- language server
		"clang-format", -- formatter
		"codelldb", -- dap

		-- CMake
		"neocmakelsp", -- language server
		"cmakelang", -- formatter, linter

		-- Docker
		"docker-compose-language-service",
		"dockerfile-language-server",
		"hadolint",

		-- Golang
		"gopls", -- language server
		"gofumpt", -- formatter
		"goimports", -- formatter
		"golangci-lint", -- linter
		"delve", -- dap

		-- Github Action
		"actionlint", -- linter

		-- Lua
		"lua-language-server", -- language server
		"stylua", -- formatter
		"luacheck", -- linter

		-- Python
		"pyright", -- language server
		"ruff", -- formatter
		"debugpy", -- dap

		-- Rust
		"rust-analyzer", -- language server

		-- FE
		"typescript-language-server", -- TypeScript language server
		"css-lsp", -- CSS language server
		"json-lsp", -- JSON language server
		"prettier", -- formatter
		-- "eslint-lsp", -- linter
		"stylelint", -- linter

		-- Misc
		"html-lsp", -- HTML language server
		"taplo", -- TOML language server
		"yaml-language-server", -- YAML language server
		"lemminx", -- XML language server
		"marksman", -- Markdown language server
		-- "cspell", -- spell checker
		"markdown-toc",
		"markdownlint-cli2",
	},
	configs = {
		stylua = {
			files = { "stylua.toml", ".stylua.toml" },
			default = vim.fn.expand("$HOME/.config/nvim/rules/stylua.toml"),
		},
		luacheck = {
			files = { ".luacheckrc" },
			default = vim.fn.expand("$HOME/.config/nvim/rules/.luacheckrc"),
		},
		-- TODO: Add clang
		-- TODO: change this to gofumpt?
		revive = {
			files = { "revive.toml" },
			default = vim.fn.expand("$HOME/.config/nvim/rules/revive.toml"),
		},
		rustfmt = {
			files = { "rustfmt.toml", ".rustfmt.toml" },
			default = vim.fn.expand("$HOME/.config/nvim/rules/rustfmt.toml"),
		},
		prettier = {
			files = {
				".prettierrc",
				".prettierrc.js",
				".prettierrc.json",
				".prettierrc.yaml",
				".prettierrc.yml",
				"prettier.config.js",
			},
			default = vim.fn.expand("$HOME/.config/nvim/rules/.prettierrc.json"),
		},
		stylelint = {
			files = {
				".stylelintrc",
				".stylelintrc.js",
				".stylelintrc.json",
				".stylelintrc.yaml",
				".stylelintrc.yml",
				"stylelint.config.js",
			},
			default = vim.fn.expand(
				"$HOME/.config/nvim/rules/stylelint/stylelint.config.js"
			),
		},
	},
}

function M.resolve_config(type)
	local config = M.configs[type]
	local cache = {}

	local function glob(cwd, dir)
		for _, file in ipairs(config.files) do
			if vim.fn.filereadable(dir .. "/" .. file) == 1 then
				cache[cwd] = dir .. "/" .. file
				return true
			end
		end
	end

	return function()
		local cwd = vim.fn.getcwd()
		if cache[cwd] then
			return cache[cwd]
		end

		if glob(cwd, cwd) then
			return cache[cwd]
		end

		for dir in vim.fs.parents(cwd) do
			if glob(cwd, dir) then
				return cache[cwd]
			end
		end

		cache[cwd] = config.default
		return cache[cwd]
	end
end

-- local eslint_default = require("lspconfig").eslint.config_def.default_config

return {
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = M.mason_tools,
		},
	},
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				bashls = {
					settings = {
						filetypes = { "sh", "bash", "zsh" },
					},
				},
				rubocop = {
					enabled = false,
				},
				pyright = {
					-- Both settings are to let Ruff handle these tasks.
					settings = {
						pyright = {
							disableOrganizeImports = true,
						},
						python = {
							analysis = {
								ignore = { "*" },
							},
						},
					},
				},
				-- TODO: How to do this properly?
				-- Idea is to have eslint handle diagnostic and linting while
				-- prettier handle formatting.
				-- eslint = {
				-- 	filetypes = {
				-- 		"json",
				-- 		"jsonc",
				-- 		"json5",
				-- 		"yaml",
				-- 		"yaml.docker-compose",
				-- 		"toml",
				-- 		unpack(eslint_default.filetypes),
				-- 	},
				-- 	root_dir = function(fname)
				-- 		return eslint_default.root_dir(fname) or vim.fs.dirname(fname)
				-- 	end,
				-- 	settings = {
				-- 		packageManager = "pnpm",
				-- 		useESLintClass = true,
				-- 		experimental = {
				-- 			useFlatConfig = true,
				-- 		},
				-- 		options = {
				-- 			overrideConfigFile = vim.fn.expand(
				-- 				"$HOME/.config/nvim/rules/eslint/eslint.config.cjs"
				-- 			),
				-- 		},
				-- 	},
				-- 	on_attach = function(client, bufnr)
				-- 		client.server_capabilities.documentFormattingProvider = true
				-- 		client.server_capabilities.documentRangeFormattingProvider = true
				-- 	end,
				-- 	mason = false,
				-- },
			},
		},
	},
	{
		"stevearc/conform.nvim",
		opts = function()
			local stylua_config = M.resolve_config("stylua")
			local rustfmt_config = M.resolve_config("rustfmt")
			local prettier_config = M.resolve_config("prettier")
			local stylelint_config = M.resolve_config("stylelint")

			return {
				formatters_by_ft = {
					-- Lua
					lua = { "stylua" },
					luau = { "stylua" },

					-- Golang
					go = { "goimports" },

					-- Rust
					rust = { "rustfmt" },

					-- Python
					python = { "ruff_format" },

					-- JavaScript
					javascript = { "prettier" },
					javascriptreact = { "prettier" },
					["javascript.jsx"] = { "prettier" },
					typescript = { "prettier" },
					typescriptreact = { "prettier" },
					["typescript.jsx"] = { "prettier" },

					-- JSON/XML
					json = { "prettier" },
					jsonc = { "prettier" },
					json5 = { "prettier" },
					yaml = { "prettier" },
					["yaml.docker-compose"] = { "prettier" },
					html = { "prettier" },

					-- Markdown
					markdown = { "prettier" },
					["markdown.mdx"] = { "prettier" },

					-- CSS
					css = { "prettier", "stylelint" },
					less = { "prettier", "stylelint" },
					sass = { "prettier", "stylelint" },
					scss = { "prettier", "stylelint" },
				},

				formatters = {
					stylua = {
						prepend_args = {
							"--config-path",
							stylua_config(),
							"--no-editorconfig",
						},
					},
					rustfmt = {
						prepend_args = { "--config-path", rustfmt_config() },
					},
					prettier = {
						prepend_args = { "--config", prettier_config() },
					},
					stylelint = {
						prepend_args = {
							"-c",
							stylelint_config(),
							"--stdin-filepath",
							"$FILENAME",
						},
					},
				},
			}
		end,
	},
	{
		"mfussenegger/nvim-lint",
		opts = {
			linters_by_ft = {
				lua = { "luacheck" },
				-- go = { "revive" },
				css = { "stylelint" },
				less = { "stylelint" },
				scss = { "stylelint" },
				sass = { "stylelint" },
				yaml = { "actionlint" },
			},

			linters = {
				luacheck = {
					cmd = "luacheck",
					args = {
						"--config",
						M.resolve_config("luacheck")(),
						"--formatter",
						"plain",
						"--codes",
						"--ranges",
						"-",
					},
					stdin = true,
					stream = "both",
				},
				-- stylelint = {
				-- 	cmd = "stylelint",
				-- 	args = {
				-- 		"-c",
				-- 		M.resolve_config("stylelint")(),
				-- 		"-f",
				-- 		"json",
				-- 		"--stdin",
				-- 		"--stdin-filename",
				-- 		vim.fn.expand("%:p"),
				-- 	},
				-- 	stdin = true,
				-- },
			},
		},
	},

	-- Integrating non-LSPs like Prettier
	-- {
	-- 	"nvimtools/none-ls.nvim",
	-- 	dependencies = {
	-- 		{ "nvim-lua/plenary.nvim", lazy = true },
	-- 		{
	-- 			"WhoIsSethDaniel/mason-tool-installer.nvim",
	-- 			opts = { ensure_installed = M.mason_tools },
	-- 		},
	-- 		{ "davidmh/cspell.nvim", lazy = true },
	-- 	},
	-- 	event = { "BufReadPre", "BufNewFile" },
	-- 	config = function()
	-- 		local nls = require("null-ls")
	-- 		local cspell = require("cspell")
	--
	-- 		nls.setup {
	-- 			sources = {
	-- 				cspell.diagnostics.with {
	-- 					diagnostics_postprocess = function(diagnostic)
	-- 						diagnostic.severity = vim.diagnostic.severity.HINT
	-- 					end,
	-- 				},
	-- 				cspell.code_actions,
	--
	-- 				nls.builtins.code_actions.gitrebase,
	-- 				nls.builtins.code_actions.gitsigns,
	-- 			},
	-- 		}
	-- 	end,
	-- },
}
