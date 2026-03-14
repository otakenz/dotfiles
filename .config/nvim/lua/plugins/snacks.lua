return {
	{
		-- https://github.com/folke/snacks.nvim/pull/2768
		-- Using fork until PR is merged
		"folke/snacks.nvim",
		url = "https://github.com/otakenz/snacks.nvim.git",
		branch = "fix/grep-file-sep-nil-guard",
		init = function()
			vim.g.snacks_animate = false
		end,
		opts = {
			dashboard = { enabled = false },
			picker = {
				hidden = true,
				sources = {
					-- These define their own options, we must override their defaults.
					files = { hidden = true },
					buffers = { hidden = true },
					-- Explorer and the rest of the sources don't define their own opts
					-- so it will use the picker options defined above and we can choose
					-- to override them if desired.
					explorer = {
						win = {
							list = {
								keys = {
									["<c-t>"] = { "tab", mode = { "n", "i" } },
								},
							},
						},
					},
				},
			},
			terminal = {
				win = {
					position = "float",
					border = "rounded",
				},
			},
		},
	},
}
