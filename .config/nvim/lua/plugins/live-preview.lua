return {
  -- TODO: switch back to upstream when PR is merged
  -- "brianhuster/live-preview.nvim",
  "otakenz/live-preview.nvim",
  branch = "feat/auto-assign-port",
  cmd = "LivePreview",
  keys = {
    { "<leader>hp", "<cmd>LivePreview start<cr>", desc = "Preview Start" },
    { "<leader>hq", "<cmd>LivePreview close<cr>", desc = "Preview Stop" },
    { "<leader>hf", "<cmd>LivePreview pick<cr>", desc = "Preview Pick" },
  },
  opts = {
    browser = "explorer.exe",
    port = 0,  -- 0 = auto-assign any free port
  },
}
