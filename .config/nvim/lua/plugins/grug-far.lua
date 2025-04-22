return {
  "MagicDuck/grug-far.nvim",

  -- Commands that trigger lazy loading
  cmd = { "GrugFar", "GrugFarWithin" },

  config = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "grug-far" },
      callback = function()
        MAP({ "i", "n", "x" }, "<A-h>", function()
          local state = unpack(
            require("grug-far").toggle_flags({ "--hidden", "--glob !.git/" })
          )
          vim.notify(
            "grug-far: toggled --hidden --glob !.git/ "
              .. (state and "ON" or "OFF")
          )
        end, { desc = "Toggle Hidden Files", buffer = true })

        MAP({ "i", "n", "x" }, "<A-i>", function()
          local state =
            unpack(require("grug-far").toggle_flags({ "--no-ignore" }))
          vim.notify(
            "grug-far: toggled --no-ignore " .. (state and "ON" or "OFF")
          )
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
        require("grug-far").open({
          visualSelectionUsage = "operate-within-range",
        })
      end,
      desc = "Within Range",
    },
  },
}
