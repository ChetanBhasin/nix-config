-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎨 ENHANCED COLOR CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

local colors = {
    bg0 = "#282828",
    bg1 = "#3c3836",
    bg2 = "#504945",
    bg3 = "#665c54",
    bg4 = "#7c6f64",
    fg0 = "#fbf1c7",
    fg1 = "#ebdbb2",
    fg2 = "#d5c4a1",
    fg3 = "#bdae93",
    fg4 = "#a89984",
    gray = "#928374",
    red = "#fb4934",
    green = "#b8bb26",
    yellow = "#fabd2f",
    blue = "#83a598",
    purple = "#d3869b",
    aqua = "#8ec07c",
    orange = "#fe8019",
}

function DefineColors(scheme)
    vim.o.background = "dark"
    local color_scheme = scheme or "gruvbox"
    vim.cmd.colorscheme(color_scheme)

    -- Enhanced transparency with better contrast
    vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
    vim.api.nvim_set_hl(0, "SignColumn", { bg = "NONE" })
    vim.api.nvim_set_hl(0, "EndOfBuffer", { bg = "NONE" })

    -- Better cursor line
    vim.api.nvim_set_hl(0, "CursorLine", { bg = colors.bg1 })
    vim.api.nvim_set_hl(0, "CursorLineNr", { fg = colors.yellow, bg = "NONE", bold = true })

    -- Enhanced search highlighting
    vim.api.nvim_set_hl(0, "Search", { bg = colors.yellow, fg = colors.bg0, bold = true })
    vim.api.nvim_set_hl(0, "IncSearch", { bg = colors.orange, fg = colors.bg0, bold = true })

    -- Better visual selection
    vim.api.nvim_set_hl(0, "Visual", { bg = colors.bg3 })

    -- Enhanced fold styling
    vim.api.nvim_set_hl(0, "Folded", { bg = colors.bg1, fg = colors.fg3, italic = true })
    vim.api.nvim_set_hl(0, "FoldColumn", { bg = "NONE", fg = colors.gray })
end

require("gruvbox").setup {
    transparent_mode = true,
    terminal_colors = true,
    contrast = "",
    dim_inactive = false,
    undercurl = true,
    underline = true,
    bold = true,
    strikethrough = true,
    invert_selection = false,
    invert_signs = false,
    invert_tabline = false,
    inverse = true,
    italic = {
        strings = false,
        emphasis = true,
        comments = true,
        operators = false,
        folds = true,
    },
    overrides = {
        NormalFloat = { bg = "NONE" },
        FloatBorder = { fg = colors.bg4, bg = "NONE" },

        Pmenu = { bg = colors.bg1, fg = colors.fg1 },
        PmenuSel = { bg = colors.bg2, fg = colors.fg0, bold = true },
        PmenuSbar = { bg = colors.bg2 },
        PmenuThumb = { bg = colors.bg4 },

        TelescopeBorder = { fg = colors.blue, bg = "NONE" },
        TelescopeSelection = { bg = colors.bg1, bold = true },
        TelescopeMatching = { fg = colors.orange, bold = true },
        TelescopePromptPrefix = { fg = colors.purple },

        NvimTreeNormal = { bg = "NONE" },
        NvimTreeEndOfBuffer = { bg = "NONE" },
        NvimTreeRootFolder = { fg = colors.purple, bold = true },
        NvimTreeFolderIcon = { fg = colors.blue },
        NvimTreeFileIcon = { fg = colors.fg1 },
        NvimTreeSpecialFile = { fg = colors.yellow, underline = true },
        NvimTreeGitDirty = { fg = colors.yellow },
        NvimTreeGitNew = { fg = colors.green },
        NvimTreeGitDeleted = { fg = colors.red },
        NvimTreeIndentMarker = { fg = colors.bg4 },

        LspReferenceText = { bg = colors.bg1 },
        LspReferenceRead = { bg = colors.bg1 },
        LspReferenceWrite = { bg = colors.bg1, bold = true },

        DiagnosticError = { fg = colors.red },
        DiagnosticWarn = { fg = colors.yellow },
        DiagnosticInfo = { fg = colors.blue },
        DiagnosticHint = { fg = colors.aqua },
        DiagnosticVirtualTextError = { fg = colors.red, bg = "NONE", italic = true },
        DiagnosticVirtualTextWarn = { fg = colors.yellow, bg = "NONE", italic = true },
        DiagnosticVirtualTextInfo = { fg = colors.blue, bg = "NONE", italic = true },
        DiagnosticVirtualTextHint = { fg = colors.aqua, bg = "NONE", italic = true },

        LspInlayHint = { fg = colors.gray, bg = "NONE", italic = true },

        LineNr = { fg = colors.bg4 },
        CursorLineNr = { fg = colors.yellow, bold = true },

        GitSignsAdd = { fg = colors.green },
        GitSignsChange = { fg = colors.yellow },
        GitSignsDelete = { fg = colors.red },

        IndentBlanklineChar = { fg = colors.bg1 },
        IndentBlanklineContextChar = { fg = colors.bg3 },

        MarkdownHeadingDelimiter = { fg = colors.orange, bold = true },
        MarkdownH1 = { fg = colors.red, bold = true },
        MarkdownH2 = { fg = colors.orange, bold = true },
        MarkdownH3 = { fg = colors.yellow, bold = true },
        MarkdownH4 = { fg = colors.green, bold = true },
        MarkdownH5 = { fg = colors.blue, bold = true },
        MarkdownH6 = { fg = colors.purple, bold = true },

        TermCursor = { fg = colors.yellow, bg = colors.yellow },
        TermCursorNC = { fg = colors.gray, bg = colors.gray },
    },
}
