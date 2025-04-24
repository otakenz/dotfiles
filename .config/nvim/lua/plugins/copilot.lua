return {
  {
    "zbirenbaum/copilot.lua",
    opts = {
      panel = { enabled = false }, -- Disable the Copilot panel
      suggestion = { enabled = false }, -- Disable the Copilot suggestion
    },
  },
  -- {
  --   "github/copilot.vim",
  --   lazy = false, -- Load on startup
  --   config = function()
  --     -- Don't let copilot map <Tab> by default
  --     vim.g.copilot_no_tab_map = true
  --     vim.g.copilot_assume_mapped = true
  --
  --     -- Accept suggestion with Tab, but only if Copilot shows something
  --     vim.api.nvim_set_keymap(
  --       "i",
  --       "<Tab>",
  --       'copilot#Accept("<CR>")',
  --       { expr = true, silent = true, replace_keycodes = false }
  --     )
  --   end,
  -- },
}
