-- ═══════════════════════════════════════════════════════════════════════════════
-- 🌈 RAINBOW DELIMITERS CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

local rainbow_delimiters = require('rainbow-delimiters')
local palette = require("custom.palette")

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

-- Use Gruvbox's full accent wheel while keeping the sequence subdued.
vim.api.nvim_set_hl(0, 'RainbowDelimiterRed', { fg = palette.base08, bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterYellow', { fg = palette.base0A, bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterBlue', { fg = palette.base0D, bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterOrange', { fg = palette.base09, bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterGreen', { fg = palette.base0B, bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterViolet', { fg = palette.base0E, bold = true })
vim.api.nvim_set_hl(0, 'RainbowDelimiterCyan', { fg = palette.base0C, bold = true })
