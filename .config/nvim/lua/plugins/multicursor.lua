return {
	{
		"jake-stewart/multicursor.nvim",
		branch = "1.0",
		config = function()
			local mc = require("multicursor-nvim")
			mc.setup()

			-- Add or skip cursor above/below the main cursor.
			MAP({ "n", "x" }, "<up>", function()
				mc.lineAddCursor(-1)
			end)
			MAP({ "n", "x" }, "<down>", function()
				mc.lineAddCursor(1)
			end)
			MAP({ "n", "x" }, "<leader><up>", function()
				mc.lineSkipCursor(-1)
			end)
			MAP({ "n", "x" }, "<leader><down>", function()
				mc.lineSkipCursor(1)
			end)

			-- Add or skip adding a new cursor by matching word/selection
			MAP({ "n", "x" }, "<leader>j", function()
				mc.matchAddCursor(1)
			end)
			MAP({ "n", "x" }, "<leader>k", function()
				mc.matchSkipCursor(1)
			end)
			MAP({ "n", "x" }, "<leader>J", function()
				mc.matchAddCursor(-1)
			end)
			MAP({ "n", "x" }, "<leader>K", function()
				mc.matchSkipCursor(-1)
			end)

			-- Add and remove cursors with CTRL + left click.
			MAP("n", "<c-leftmouse>", mc.handleMouse)
			MAP("n", "<c-leftdrag>", mc.handleMouseDrag)
			MAP("n", "<c-leftrelease>", mc.handleMouseRelease)

			-- Mappings defined in a keymap layer only apply when there are
			-- multiple cursors. This lets you have overlapping mappings.
			mc.addKeymapLayer(function(layerSet)
				-- select a different cursor as the main one.
				-- layerSet({ "n", "x" }, "<left>", mc.prevcursor)
				-- layerSet({ "n", "x" }, "<right>", mc.nextcursor)

				-- Enable and clear cursors using escape.
				layerSet("n", "<esc>", function()
					if not mc.cursorsEnabled() then
						mc.enableCursors()
					else
						mc.clearCursors()
					end
				end)
			end)
		end,
	},
}
