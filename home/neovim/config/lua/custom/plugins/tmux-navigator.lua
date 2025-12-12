-- vim-tmux-navigator configuration
-- Seamless navigation between tmux panes and vim splits

-- Disable default mappings (we'll set our own through which-key if needed)
vim.g.tmux_navigator_no_mappings = 0

-- Save on switch (optional - saves buffer when navigating away)
vim.g.tmux_navigator_save_on_switch = 1

-- Disable when zoomed (don't navigate when tmux pane is zoomed)
vim.g.tmux_navigator_disable_when_zoomed = 1

-- Preserve zoom state when navigating
vim.g.tmux_navigator_preserve_zoom = 1

-- Key mappings for navigation
-- These work seamlessly between vim splits and tmux panes
vim.keymap.set('n', '<C-h>', '<Cmd>TmuxNavigateLeft<CR>', { silent = true, desc = 'Navigate left (vim/tmux)' })
vim.keymap.set('n', '<C-j>', '<Cmd>TmuxNavigateDown<CR>', { silent = true, desc = 'Navigate down (vim/tmux)' })
vim.keymap.set('n', '<C-k>', '<Cmd>TmuxNavigateUp<CR>', { silent = true, desc = 'Navigate up (vim/tmux)' })
vim.keymap.set('n', '<C-l>', '<Cmd>TmuxNavigateRight<CR>', { silent = true, desc = 'Navigate right (vim/tmux)' })
vim.keymap.set('n', '<C-\\>', '<Cmd>TmuxNavigatePrevious<CR>', { silent = true, desc = 'Navigate to previous pane' })
