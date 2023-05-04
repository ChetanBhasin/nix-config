local M = {}

M.ui = {
  theme = 'catppuccin',
}

M.plugins = "custom.plugins"
M.mapping = {
  crates = {
    n = {
      ["<leader>rcu"] = {
        function()
          require("crates").upgrade_all_crates()
        end,
        "Upgrade all crates",
      }
    }
  }
}

return M
