-- ═══════════════════════════════════════════════════════════════════════════════
-- 🦎 LAZYJJ CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Floating window integration for lazyjj TUI (Jujutsu version control)

-- Note: lazyjj.nvim doesn't support disabling its default keymap cleanly.
-- We skip calling setup() to avoid duplicate keybindings.
-- The :LazyJJ command is still available, and we define our keybinding in keymaps.lua.

-- Verify the plugin is available (for :LazyJJ command)
local ok = pcall(require, "lazyjj")
if not ok then
    vim.notify("lazyjj.nvim not found", vim.log.levels.WARN)
end

-- Note: All keybindings are centralized in keymaps.lua for discoverability via Legendary
-- See: <leader>? to search all keybindings
--
-- Available commands:
--   :LazyJJ - Open lazyjj in a floating window
