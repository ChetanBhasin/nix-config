-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔔 MINI.NOTIFY CONFIGURATION (replaces nvim-notify/snacks notifier)
-- ═══════════════════════════════════════════════════════════════════════════════

local ok, mini_notify = pcall(require, "mini.notify")
if not ok then
  return
end

mini_notify.setup({
  -- Do not compete with fidget.nvim for LSP progress UI
  lsp_progress = { enable = false },

  -- Window styling
  window = {
    width = 0.35,
    max_width_share = 0.5,
    max_height_share = 0.3,
    border = "rounded",
    zindex = 60,
  },

  -- Content formatting
  content = {
    format = function(notif)
      -- Handle both string and table message formats
      local msg_text
      if type(notif.msg) == "table" then
        msg_text = table.concat(notif.msg, "\n")
      else
        msg_text = tostring(notif.msg)
      end

      -- Keep messages concise; show title when present
      if notif.title and notif.title ~= "" then
        return string.format("%s\n%s", notif.title, msg_text)
      end
      return msg_text
    end,
  },
})

-- Make Mini Notify the default notifier
vim.notify = mini_notify.make_notify()

