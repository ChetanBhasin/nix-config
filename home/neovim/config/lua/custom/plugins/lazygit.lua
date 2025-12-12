-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔀 LAZYGIT CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Floating window integration for lazygit TUI

-- Configuration options
vim.g.lazygit_floating_window_winblend = 0 -- Transparency (0 = opaque)
vim.g.lazygit_floating_window_scaling_factor = 0.9 -- Window size (90% of screen)
vim.g.lazygit_floating_window_border_chars = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
vim.g.lazygit_floating_window_use_plenary = 0 -- Use plenary for window (0 = native)
vim.g.lazygit_use_neovim_remote = 1 -- Enable neovim-remote for editing commits

-- Note: All keybindings are centralized in keymaps.lua for discoverability via Legendary
-- See: <leader>? to search all keybindings
--
-- Available commands:
--   :LazyGit                    - Open lazygit in current working directory
--   :LazyGitCurrentFile         - Open lazygit in project root of active file
--   :LazyGitConfig              - Open lazygit configuration file
--   :LazyGitFilter              - Show project commits
--   :LazyGitFilterCurrentFile   - Show buffer-specific commits
