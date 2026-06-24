return {
  "brianhuster/live-preview.nvim",
  cmd = "LivePreview",
  keys = {
    { "<leader>hp", "<cmd>LivePreview start<cr>", desc = "Preview Start" },
    { "<leader>hq", "<cmd>LivePreview close<cr>", desc = "Preview Stop" },
    { "<leader>hf", "<cmd>LivePreview pick<cr>", desc = "Preview Pick" },
  },
  opts = {
    browser = "explorer.exe",
    port = 8080,
  },
}
