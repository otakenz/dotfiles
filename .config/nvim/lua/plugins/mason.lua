return {
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				-- Shell
				"bash-language-server",
				"shellcheck",
				"shfmt",
				-- Clang
				"clang-format",
				"clangd",
				"codelldb",
				-- CMake
				"cmakelang",
				"neocmakelsp",
				-- Docker
				"docker-compose-language-service",
				"dockerfile-language-server",
				"hadolint",
				-- Go
				"delve",
				"gofumpt",
				"goimports",
				"golangci-lint",
				"gopls",
				-- Lua
				"lua-language-server",
				"stylua",
				-- Python
				"debugpy",
				"pyright",
				"ruff",
				-- Json, Markdown, Yaml, Toml
				"json-lsp",
				"markdown-toc",
				"markdownlint-cli2",
				"marksman",
				"prettier",
				"taplo",
				"yaml-language-server",
				-- Rust
				"rust-analyzer",
			},
		},
	},
}
