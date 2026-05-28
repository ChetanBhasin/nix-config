-- ═══════════════════════════════════════════════════════════════════════════════
-- 📏 INDENT BLANKLINE CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

require("ibl").setup {
    indent = {
        char = "│",
        tab_char = "│",
        highlight = { "IndentBlanklineChar" },
        smart_indent_cap = true,
    },
    whitespace = {
        highlight = { "Whitespace" },
        remove_blankline_trail = true,
    },
    scope = {
        enabled = true,
        char = "│",
        highlight = { "IndentBlanklineContextChar" },
        show_start = true,
        show_end = false,
        injected_languages = false,
        priority = 1024,
        include = {
            node_type = {
                ["*"] = {
                    "class",
                    "return_statement",
                    "function",
                    "method",
                    "^if",
                    "^while",
                    "jsx_element",
                    "^for",
                    "^object",
                    "^table",
                    "block",
                    "arguments",
                    "if_statement",
                    "else_clause",
                    "jsx_element",
                    "jsx_self_closing_element",
                    "try_statement",
                    "catch_clause",
                    "import_statement",
                    "operation_type",
                },
            },
        },
        exclude = {
            language = { "help", "alpha", "dashboard", "neo-tree", "Trouble", "trouble", "lazy", "mason", "toggleterm", "lazyterm" },
            node_type = {
                ["*"] = { "source_file", "program" },
                lua = { "chunk" },
                python = { "module" },
            },
        },
    },
    exclude = {
        filetypes = {
            "help",
            "alpha",
            "dashboard",
            "neo-tree",
            "Trouble",
            "trouble",
            "lazy",
            "mason",
            "toggleterm",
            "lazyterm",
        },
        buftypes = { "terminal", "nofile" },
    },
}

-- Custom highlight groups for better visibility
vim.api.nvim_set_hl(0, "IndentBlanklineChar", { fg = "#3c3836", nocombine = true })
vim.api.nvim_set_hl(0, "IndentBlanklineContextChar", { fg = "#665c54", nocombine = true })
vim.api.nvim_set_hl(0, "Whitespace", { fg = "#3c3836" })
