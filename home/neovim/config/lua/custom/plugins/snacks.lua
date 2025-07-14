-- ═══════════════════════════════════════════════════════════════════════════════
-- 🍿 SNACKS.NVIM CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

local snacks = require("snacks")

snacks.setup {
  -- Enable the notifier module for enhanced notifications
  notifier = {
    enabled = true,
    timeout = 3000,
    style = "compact",
    top_down = true,
    margin = { top = 0, right = 1, bottom = 0, left = 1 },
    icons = {
      error = " ",
      warn = " ",
      info = " ",
      debug = " ",
      trace = " ",
    },
    keep = function(notif)
      return vim.fn.fnamemodify(notif.msg[1], ":t") ~= "mini.nvim"
    end,
    sort = { "level", "added" },
  },
  -- Disable other modules we don't need
  bigfile = { enabled = false },
  quickfile = { enabled = false },
  statuscolumn = { enabled = false },
  words = { enabled = false },
  styles = {
    notification = {
      wo = { wrap = true },
      border = "rounded",
    },
  },
}

-- Override vim.notify to use snacks notifier
vim.notify = snacks.notify