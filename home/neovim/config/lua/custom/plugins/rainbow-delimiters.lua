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

-- Custom highlight groups using the Gruvbox Night accents
vim.api.nvim_set_hl(0, 'RainbowDelimiterRed', { fg = '#db7e75', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterYellow', { fg = '#c9a257', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterBlue', { fg = '#84a9b2', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterOrange', { fg = '#d58a54', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterGreen', { fg = '#a3ad62', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterViolet', { fg = '#c38da0', bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterCyan', { fg = '#7fa98a', bold = true })
