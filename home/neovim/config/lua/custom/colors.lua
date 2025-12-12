-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎨 ENHANCED COLOR CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

function DefineColors(scheme)
    local color_scheme = scheme or "catppuccin-mocha"
    vim.cmd.colorscheme(color_scheme)

    -- Enhanced transparency with better contrast
    vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
    vim.api.nvim_set_hl(0, "SignColumn", { bg = "none" })
    vim.api.nvim_set_hl(0, "EndOfBuffer", { bg = "none" })

    -- Better cursor line
    vim.api.nvim_set_hl(0, "CursorLine", { bg = "#313244" })
    vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#f9e2af", bg = "none", bold = true })

    -- Enhanced search highlighting
    vim.api.nvim_set_hl(0, "Search", { bg = "#f9e2af", fg = "#1e1e2e", bold = true })
    vim.api.nvim_set_hl(0, "IncSearch", { bg = "#fab387", fg = "#1e1e2e", bold = true })

    -- Better visual selection
    vim.api.nvim_set_hl(0, "Visual", { bg = "#585b70" })

    -- Enhanced fold styling
    vim.api.nvim_set_hl(0, "Folded", { bg = "#313244", fg = "#a6adc8", italic = true })
    vim.api.nvim_set_hl(0, "FoldColumn", { bg = "none", fg = "#6c7086" })
end

require("catppuccin").setup {
    flavour = "mocha", -- latte, frappe, macchiato, mocha
    background = {     -- :h background
        light = "latte",
        dark = "mocha",
    },
    transparent_background = true,
    show_end_of_buffer = false,
    term_colors = true,
    dim_inactive = {
        enabled = false,
        shade = "dark",
        percentage = 0.15,
    },
    no_italic = false,
    no_bold = false,
    no_underline = false,
    styles = {
        comments = { "italic" },
        conditionals = { "bold" },
        loops = { "bold" },
        functions = { "bold" },
        keywords = { "bold" },
        strings = {},
        variables = {},
        numbers = {},
        booleans = { "bold" },
        properties = {},
        types = { "italic" },
        operators = {},
    },
    color_overrides = {
        mocha = {
            base = "#000000",   -- Make base fully transparent
            mantle = "#000000", -- Make mantle fully transparent
            crust = "#000000",  -- Make crust fully transparent
        },
    },
    custom_highlights = function(colors)
        return {
            -- Floating windows with subtle borders
            NormalFloat = { bg = colors.none },
            FloatBorder = { fg = colors.surface2, bg = colors.none },

            -- Better completion menu
            Pmenu = { bg = colors.surface0, fg = colors.text },
            PmenuSel = { bg = colors.surface1, fg = colors.text, bold = true },
            PmenuSbar = { bg = colors.surface1 },
            PmenuThumb = { bg = colors.overlay0 },

            -- Enhanced telescope
            TelescopeBorder = { fg = colors.blue, bg = colors.none },
            TelescopeSelection = { bg = colors.surface1, bold = true },
            TelescopeMatching = { fg = colors.peach, bold = true },
            TelescopePromptPrefix = { fg = colors.flamingo },

            -- Better nvim-tree
            NvimTreeNormal = { bg = colors.none },
            NvimTreeEndOfBuffer = { bg = colors.none },
            NvimTreeRootFolder = { fg = colors.pink, bold = true },
            NvimTreeFolderIcon = { fg = colors.blue },
            NvimTreeFileIcon = { fg = colors.text },
            NvimTreeSpecialFile = { fg = colors.yellow, underline = true },
            NvimTreeGitDirty = { fg = colors.yellow },
            NvimTreeGitNew = { fg = colors.green },
            NvimTreeGitDeleted = { fg = colors.red },
            NvimTreeIndentMarker = { fg = colors.surface2 },

            -- Enhanced LSP highlights
            LspReferenceText = { bg = colors.surface1 },
            LspReferenceRead = { bg = colors.surface1 },
            LspReferenceWrite = { bg = colors.surface1, bold = true },

            -- Better diagnostic highlights
            DiagnosticError = { fg = colors.red },
            DiagnosticWarn = { fg = colors.yellow },
            DiagnosticInfo = { fg = colors.sky },
            DiagnosticHint = { fg = colors.teal },
            DiagnosticVirtualTextError = { fg = colors.red, bg = colors.none, italic = true },
            DiagnosticVirtualTextWarn = { fg = colors.yellow, bg = colors.none, italic = true },
            DiagnosticVirtualTextInfo = { fg = colors.sky, bg = colors.none, italic = true },
            DiagnosticVirtualTextHint = { fg = colors.teal, bg = colors.none, italic = true },

            -- Enhanced inlay hints
            LspInlayHint = { fg = colors.overlay0, bg = colors.none, italic = true },

            -- Better line numbers
            LineNr = { fg = colors.surface2 },
            CursorLineNr = { fg = colors.peach, bold = true },

            -- Enhanced git signs
            GitSignsAdd = { fg = colors.green },
            GitSignsChange = { fg = colors.yellow },
            GitSignsDelete = { fg = colors.red },

            -- Better indentation guides (if using indent-blankline)
            IndentBlanklineChar = { fg = colors.surface1 },
            IndentBlanklineContextChar = { fg = colors.surface2 },

            -- Enhanced markdown
            MarkdownHeadingDelimiter = { fg = colors.peach, bold = true },
            MarkdownH1 = { fg = colors.red, bold = true },
            MarkdownH2 = { fg = colors.orange, bold = true },
            MarkdownH3 = { fg = colors.yellow, bold = true },
            MarkdownH4 = { fg = colors.green, bold = true },
            MarkdownH5 = { fg = colors.blue, bold = true },
            MarkdownH6 = { fg = colors.purple, bold = true },

            -- Better terminal colors
            TermCursor = { fg = colors.rosewater, bg = colors.rosewater },
            TermCursorNC = { fg = colors.overlay1, bg = colors.overlay1 },
        }
    end,
    integrations = {
        -- Enable bufferline integration; the bufferline module also guards
        -- against API changes when applying highlights.
        bufferline = true,
        cmp = true,
        gitsigns = true,
        nvimtree = true,
        treesitter = true,
        telescope = {
            enabled = true,
            style = "nvchad"
        },
        harpoon = false,
        mason = true,
        fidget = true,
        which_key = true,
        lsp_trouble = true,
        dap = {
            enabled = true,
            enable_ui = true,
        },
        native_lsp = {
            enabled = true,
            virtual_text = {
                errors = { "italic" },
                hints = { "italic" },
                warnings = { "italic" },
                information = { "italic" },
            },
            underlines = {
                errors = { "underline" },
                hints = { "underline" },
                warnings = { "underline" },
                information = { "underline" },
            },
            inlay_hints = {
                background = true,
            },
        },
    },
}
