return {
	{
		"yetone/avante.nvim",

		opts = {
			mode = "agentic", -- or "legacy"
			provider = "copilot",
			providers = {
				copilot = {
					model = "gpt-4.1",
					-- model = "gpt-5-mini",
				},
			},
			behaviour = {
				auto_set_keymaps = true,
			},
		},
	},
}
