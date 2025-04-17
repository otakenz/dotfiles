-- Keymaps are automatically loaded on the VeryLazy event.
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

MAP("n", "<leader>ll", "<Cmd>Lazy<CR>", { desc = "Lazy" })
MAP("n", "<leader>lL", "<Cmd>LazyExtras<CR>", { desc = "Lazy Extras" })

-- In normal mode, map Ctrl+k/j to move the current line up/down by count
MAP(
  "n",
  "<C-k>",
  "<Cmd>execute 'move .-' . (v:count1 + 1)<CR>==",
  { desc = "Move Up" }
)
MAP(
  "n",
  "<C-j>",
  "<Cmd>execute 'move .+' . v:count1<CR>==",
  { desc = "Move Down" }
)

-- In insert mode, map Ctrl+k/j to move the current line up/down and return to insert mode
MAP("i", "<C-k>", "<esc><Cmd>m .-2<CR>==gi", { desc = "Move Up" })
MAP("i", "<C-j>", "<esc><Cmd>m .+1<CR>==gi", { desc = "Move Down" })

-- In visual mode, map Ctrl+k/j to move the current line/blocks up/down by count
MAP(
  "x",
  "<C-k>",
  ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<CR>gv=gv",
  { desc = "Move Up" }
)
MAP(
  "x",
  "<C-j>",
  ":<C-u>execute \"'<,'>move '>+\" . v:count1<CR>gv=gv",
  { desc = "Move Down" }
)

--MAP("n", "<leader>nh", ":nohl<CR>", { desc = "Clear search highlights" })
