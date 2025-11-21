return {
	"MagicDuck/grug-far.nvim",

	-- Commands that trigger lazy loading
	cmd = { "GrugFar", "GrugFarWithin" },

	config = function(_, opts)
		require("grug-far").setup(opts)

		vim.api.nvim_create_autocmd("FileType", {
			pattern = { "grug-far" },
			callback = function()
				MAP({ "i", "n", "x" }, "<A-h>", function()
					local state =
						unpack(require("grug-far").get_instance(0):toggle_flags({ "--hidden", "--glob !.git/" }))
					vim.notify("grug-far: toggled --hidden --glob !.git/ " .. (state and "ON" or "OFF"))
				end, { desc = "Toggle Hidden Files", buffer = true })
			end,
		})

		vim.api.nvim_create_autocmd("FileType", {
			pattern = { "grug-far" },
			callback = function()
				MAP({ "i", "n", "x" }, "<A-i>", function()
					local state = unpack(require("grug-far").get_instance(0):toggle_flags({ "--no-ignore" }))
					vim.notify("grug-far: toggled --no-ignore " .. (state and "ON" or "OFF"))
				end, { desc = "Toggle Ignored Files", buffer = true })
			end,
		})
	end,

	-- Keys are lazy loaded
	keys = {
		{
			"<leader>sRa",
			mode = { "v" },
			function()
				require("grug-far").with_visual_selection()
			end,
			desc = "All Files",
		},
		{
			"<leader>sRc",
			function()
				require("grug-far").open({
					prefills = { paths = vim.fn.expand("%") },
				})
			end,
			desc = "Current File",
		},
		{
			"<leader>sRc",
			mode = { "v" },
			function()
				require("grug-far").with_visual_selection({
					prefills = { paths = vim.fn.expand("%") },
				})
			end,
			desc = "Current File",
		},
		{
			"<leader>sRw",
			mode = { "v" },
			function()
				local search = vim.fn.getreg("/")
				-- Remove \V prefix if present
				if search and vim.startswith(search, "\\V") then
					search = search:sub(3)
				end
				-- Remove surround if "word" search (such as when pressing `*`)
				if search and vim.startswith(search, "\\<") and vim.endswith(search, "\\>") then
					search = "\\b" .. search:sub(3, -3) .. "\\b"
				end
				require("grug-far").open({
					visualSelectionUsage = "operate-within-range",
					prefills = { search = search },
				})
			end,
			desc = "Within Range",
		},
	},
}
