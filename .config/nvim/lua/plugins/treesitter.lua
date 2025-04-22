return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      -- Lazy.nvim package manager will mega-merge ensure_installed
      ensure_installed = {
        "csv",
        "dockerfile",
        "go",
        "ron",
        "ruby",
        "terraform",
        "toml",
      },
    },
  },
}
