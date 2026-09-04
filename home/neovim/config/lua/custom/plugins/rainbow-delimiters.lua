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

-- Custom highlight groups using Luna's accents
vim.api.nvim_set_hl(0, 'RainbowDelimiterRed', { fg = '#e08585', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterYellow', { fg = '#d9a35a', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterBlue', { fg = '#75a1c7', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterOrange', { fg = '#e19067', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterGreen', { fg = '#9eb38e', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterViolet', { fg = '#c4a8d6', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterCyan', { fg = '#8c9cb8', bold = true })
