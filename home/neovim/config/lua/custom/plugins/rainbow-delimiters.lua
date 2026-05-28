-- ═══════════════════════════════════════════════════════════════════════════════
-- 🌈 RAINBOW DELIMITERS CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

local rainbow_delimiters = require('rainbow-delimiters')

vim.g.rainbow_delimiters = {
    strategy = {
        [''] = rainbow_delimiters.strategy['global'],
        vim = rainbow_delimiters.strategy['local'],
    },
    query = {
        [''] = 'rainbow-delimiters',
        lua = 'rainbow-blocks',
    },
    priority = {
        [''] = 110,
        lua = 210,
    },
    highlight = {
        'RainbowDelimiterRed',
        'RainbowDelimiterYellow',
        'RainbowDelimiterBlue',
        'RainbowDelimiterOrange',
        'RainbowDelimiterGreen',
        'RainbowDelimiterViolet',
        'RainbowDelimiterCyan',
    },
}

-- Custom highlight groups using gruvbox dark colors
vim.api.nvim_set_hl(0, 'RainbowDelimiterRed', { fg = '#fb4934', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterYellow', { fg = '#fabd2f', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterBlue', { fg = '#83a598', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterOrange', { fg = '#fe8019', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterGreen', { fg = '#b8bb26', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterViolet', { fg = '#d3869b', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterCyan', { fg = '#8ec07c', bold = true })
