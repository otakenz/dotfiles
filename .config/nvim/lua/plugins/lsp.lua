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
		-- "stylelint", -- linter

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
		cmakeformat = {
			files = {
				".cmake-format.yaml",
				".cmake-format.yml",
				"cmake-format.yaml",
				"cmake-format.yml",
			},
			default = vim.fn.expand("$HOME/.config/nvim/rules/.cmake-format.yaml"),
		},
		cmakelint = {
			files = {
				".cmakelintrc",
				"cmakelintrc",
			},
			default = vim.fn.expand("$HOME/.config/nvim/rules/.cmakelintrc"),
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
				neocmake = {
					init_options = {
						-- cmake-format handles formatting
						format = {
							enable = false,
						},
						-- cmakelint (not cmake-lint) handles linting
						lint = {
							enable = false,
						},
					},
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
			},
		},
	},
	{
		"stevearc/conform.nvim",
		opts = {
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
				css = { "prettier" },
				less = { "prettier" },
				sass = { "prettier" },
				scss = { "prettier" },

				-- Cmake
				cmake = { "cmake_format" },
			},

			formatters = {
				stylua = {
					prepend_args = {
						"--config-path",
						M.resolve_config("stylua")(),
						"--no-editorconfig",
					},
				},
				rustfmt = {
					prepend_args = { "--config-path", M.resolve_config("rustfmt")() },
				},
				prettier = {
					prepend_args = { "--config", M.resolve_config("prettier")() },
				},
				cmake_format = {
					append_args = {
						"-c",
						M.resolve_config("cmakeformat")(),
					},
				},
			},
		},
	},
	{
		"mfussenegger/nvim-lint",
		opts = {
			linters_by_ft = {
				lua = { "luacheck" },
				-- yaml = { "actionlint" },
				cmake = { "cmakelint" },
			},

			linters = {
				luacheck = {
					args = {
						"--config",
						M.resolve_config("luacheck")(),
						"--formatter",
						"plain",
						"--codes",
						"--ranges",
						"-",
					},
				},
				cmakelint = {
					args = {
						"--quiet",
						"--config",
						M.resolve_config("cmakelint")(),
					},
				},
			},
		},
	},
}
