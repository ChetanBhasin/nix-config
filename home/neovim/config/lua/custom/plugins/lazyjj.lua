-- ═══════════════════════════════════════════════════════════════════════════════
-- 🦎 LAZYJJ CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Floating window integration for lazyjj TUI (Jujutsu version control)

-- The :LazyJJ command is registered by setup(). Disable lazyjj.nvim's own
-- keymap so the binding stays centralized in keymaps.lua/Legendary.

local ok, lazyjj = pcall(require, "lazyjj")
if ok then
    lazyjj.setup({ mapping = false })
else
    vim.notify("lazyjj.nvim not found", vim.log.levels.WARN)
end

-- Note: All keybindings are centralized in keymaps.lua for discoverability via Legendary
-- See: <leader>? to search all keybindings
--
-- Available commands:
--   :LazyJJ - Open lazyjj in a floating window
