return {
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
	{
		"NickvanDyke/opencode.nvim",
		dependencies = {
			"folke/snacks.nvim",
			opts = { input = {}, picker = {}, terminal = {} },
		},
		config = function()
			vim.g.opencode_opts = {
				-- Your configuration, if any — see `lua/opencode/config.lua`, or "goto definition".
				provider = {
					enabled = "snacks",
					snacks = {
						win = {
							enter = true, -- Stay in the editor after opening the terminal
						},
					},
				},
			}

			-- Required for `opts.auto_reload`.
			vim.o.autoread = true

			-- Keymaps for opencode.nvim
			vim.keymap.set({ "n", "x" }, "<leader>aa", function()
				require("opencode").ask("@this: ", { submit = true })
			end, { desc = "Ask opencode" })

			vim.keymap.set({ "n", "x" }, "<leader>ap", function()
				require("opencode").select()
			end, { desc = "Execute opencode action…" })

			vim.keymap.set({ "n", "x" }, "<leader>ad", function()
				require("opencode").prompt("@this")
			end, { desc = "Add to opencode" })

			vim.keymap.set({ "n", "t" }, "<leader>at", function()
				require("opencode").toggle()
			end, { desc = "Toggle opencode" })
		end,
	},
}
