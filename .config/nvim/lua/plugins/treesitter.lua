return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts_extend = { "ensure_installed" },
    opts = {
      -- Identation was often misgaligned, especially with list items. This
      -- lets Neovim handle indentation directly. This is a bug with Treesitter
      -- and should be fixed in 1.0.
      indent = {
        disable = { "yaml" },
      },
      -- Lazy.nvim package manager will mega-merge ensure_installed
      ensure_installed = {
        "bash",
        "bitbake",
        "c",
        "cmake",
        "cpp",
        "csv",
        "dockerfile",
        "go",
        "json",
        "lua",
        "python",
        "ron",
        "rust",
        -- "tmux",
        "toml",
        "xml",
        "yaml",
      },
    },
  },
}
