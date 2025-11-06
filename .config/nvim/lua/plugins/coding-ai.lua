return {
	{
		"yetone/avante.nvim",

		opts = {
			mode = "agentic", -- or "legacy"
			provider = "copilot",
			rules = {
				project_dir = ".avante/rules", -- relative to project root, can also be an absolute path
				global_dir = "~/.config/avante/rules", -- absolute path
			},
			providers = {
				copilot = {
					model = "gpt-4.1",
					-- model = "gpt-5-mini",
					disable_tools = false, -- disables all tools when true
					-- To selectively disable tools (like only 'python'), use:
					-- disabled_tools = { "python" },
				},
			},
			behaviour = {
				auto_set_keymaps = true,
				auto_suggestions = false,
			},
			windows = {
				width = 45,
			},
		},
		keys = false,
	},

	{
		"ravitemer/mcphub.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
		},
		build = "npm install -g mcp-hub@latest", -- Installs `mcp-hub` node binary globally
		opts = {
			auto_approve = false, -- Auto approve all MCP tool calls
			port = 37373,
			global_env = {}, -- Global environment variables available to all MCP servers (can be a table or a function returning a table)
			workspace = {
				enabled = true, -- Enable project-local configuration files
				look_for = {
					".mcphub/servers.json",
					".vscode/mcp.json",
					".cursor/mcp.json",
				}, -- Files to look for when detecting project boundaries (VS Code format supported)
			},
		},
	},
}
