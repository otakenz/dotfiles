-- Keymaps are automatically loaded on the VeryLazy event.
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

MAP("n", "<leader>ll", "<Cmd>Lazy<CR>", { desc = "Lazy" })
MAP("n", "<leader>lL", "<Cmd>LazyExtras<CR>", { desc = "Lazy Extras" })

-- In normal mode, map Ctrl+k/j to move the current line up/down by count
MAP(
	"n",
	"<C-p>",
	"<Cmd>execute 'move .-' . (v:count1 + 1)<CR>==",
	{ desc = "Move Up" }
)
MAP(
	"n",
	"<C-n>",
	"<Cmd>execute 'move .+' . v:count1<CR>==",
	{ desc = "Move Down" }
)

-- In insert mode, map Ctrl+k/j to move the current line up/down and return to insert mode
MAP("i", "<C-p>", "<esc><Cmd>m .-2<CR>==gi", { desc = "Move Up" })
MAP("i", "<C-n>", "<esc><Cmd>m .+1<CR>==gi", { desc = "Move Down" })

-- In visual mode, map Ctrl+k/j to move the current line/blocks up/down by count
MAP(
	"x",
	"<C-p>",
	":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<CR>gv=gv",
	{ desc = "Move Up" }
)
MAP(
	"x",
	"<C-n>",
	":<C-u>execute \"'<,'>move '>+\" . v:count1<CR>gv=gv",
	{ desc = "Move Down" }
)

MAP({ "n", "x" }, "x", '"_x', { desc = "Delete Chars Into Void" })
MAP({ "n", "x" }, "X", '"_x', { desc = "Delete Chars Into Void" })
MAP({ "n", "x" }, "<Del>", '"_x', { desc = "Delete Chars Into Void" })

MAP("x", "y", "ygv<Esc>", { desc = "Yank Preserve Cursor" })
MAP("x", "p", "P", { desc = "Paste Without Override" })

MAP("n", "<leader>uW", ":set list!<CR>", { desc = "Toggle WhiteSpace" })

MAP("n", "<leader>bc", ":let @+ = expand('%:.')<CR>", { desc = "Copy Path" })

MAP(
	"x",
	"gt",
	"c<C-r>=system('tcc', getreg('\"'))[:-2]<CR>",
	{ desc = "Titleize Text" }
)

MAP("v", "<Tab>", ">gv", { desc = "Indent right" })
MAP("v", "<S-Tab>", "<gv", { desc = "Indent left" })

MAP(
	{ "n" },
	"<leader>r",
	":%s///g<Left><Left>",
	{ desc = "Search and replace" }
)

MAP(
	{ "x" },
	"<leader>r",
	":s///g<Left><Left>",
	{ desc = "Search and replace (Visual)" }
)
