-- Treesitter Plugin Setup
require('nvim-treesitter.configs').setup {
    autopairs = {
        enable = true
    },
    highlight = {
        enable = true,
    },
    ident = { enable = true },
    rainbow = {
        enable = true,
        extended_mode = true,
        max_file_lines = nil,
    }
}
