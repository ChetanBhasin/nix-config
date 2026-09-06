-- Gruvbox Night: custom hard-dark surfaces with restrained, warm accents.
-- The shared palette lives in custom.palette; this file owns highlight behavior.

local colors = require("custom.palette")

local function highlight(name, value)
    vim.api.nvim_set_hl(0, name, value)
end

function DefineColors()
    vim.o.background = "dark"

    -- Base16 supplies broad syntax coverage; the overrides below refine focused
    -- states and plugin surfaces without requiring a separate colorscheme plugin.
    require("base16-colorscheme").setup(colors)
    vim.g.colors_name = "gruvbox-night"

    -- Keep ordinary surfaces calm while making active UI consistently orange.
    highlight("Normal", { fg = colors.base05, bg = colors.base00 })
    highlight("NormalNC", { fg = colors.base04, bg = colors.base00 })
    highlight("NormalFloat", { fg = colors.base05, bg = colors.base01 })
    highlight("SignColumn", { bg = colors.base00 })
    highlight("EndOfBuffer", { fg = colors.base00, bg = colors.base00 })
    highlight("FloatBorder", { fg = colors.soft_neutral, bg = colors.base01 })
    highlight("WinSeparator", { fg = colors.base02, bg = colors.base00 })
    highlight("VertSplit", { fg = colors.base02, bg = colors.base00 })

    highlight("Comment", { fg = colors.soft_neutral, italic = true })
    highlight("@comment", { link = "Comment" })
    highlight("@lsp.type.comment", { link = "Comment" })

    highlight("Pmenu", { fg = colors.base05, bg = colors.base01 })
    highlight("PmenuSel", { fg = colors.primary_accent, bg = colors.primary_surface, bold = true })
    highlight("LspSignatureActiveParameter", { fg = colors.primary_accent, bg = colors.primary_surface, bold = true })
    highlight("WildMenu", { fg = colors.primary_accent, bg = colors.primary_surface, bold = true })
    highlight("QuickFixLine", { fg = colors.primary_accent, bg = colors.primary_surface, bold = true })
    highlight("TabLineSel", { fg = colors.primary_accent, bg = colors.base00, bold = true })
    highlight("BlinkCmpMenuSelection", { fg = colors.primary_accent, bg = colors.primary_surface, bold = true })
    highlight("BlinkCmpSignatureHelpActiveParameter", { fg = colors.primary_accent, bold = true })
    highlight("FzfLuaCursor", { fg = colors.primary_accent, bg = colors.base01, bold = true })
    highlight("FzfLuaSelected", { fg = colors.primary_accent, bg = colors.base01, bold = true })
    highlight("GrappleCurrent", { fg = colors.primary_accent, bold = true })
    highlight("AvanteFileSelectorSelection", { fg = colors.primary_accent, bg = colors.base01, bold = true })

    highlight("CursorLine", { bg = colors.base01 })
    highlight("CursorLineNr", { fg = colors.primary_accent, bg = colors.base01, bold = true })
    highlight("LineNr", { fg = colors.dim_neutral, bg = colors.base00 })

    highlight("Visual", { fg = colors.base06, bg = colors.base02 })
    highlight("Search", { fg = colors.signal, bg = colors.primary_surface, bold = true })
    highlight("IncSearch", { fg = colors.base00, bg = colors.primary_accent, bold = true })
    highlight("CurSearch", { fg = colors.base00, bg = colors.primary_accent, bold = true })
    highlight("Substitute", { fg = colors.base00, bg = colors.primary_accent, bold = true })

    highlight("Folded", { bg = colors.base01, fg = colors.base03 })
    highlight("FoldColumn", { bg = colors.base00, fg = colors.base03 })

    highlight("TelescopeBorder", { fg = colors.soft_neutral, bg = colors.base00 })
    highlight("TelescopeSelection", { fg = colors.primary_accent, bg = colors.primary_surface, bold = true })
    highlight("TelescopeSelectionCaret", { fg = colors.primary_accent, bg = colors.primary_surface, bold = true })
    highlight("TelescopeMatching", { fg = colors.signal, bold = true })
    highlight("TelescopePromptPrefix", { fg = colors.primary_accent })
    highlight("TelescopePromptBorder", { fg = colors.primary_accent, bg = colors.base00 })
    highlight("FzfLuaPromptBorder", { fg = colors.primary_accent, bg = colors.base00 })
    highlight("FzfLuaPromptPrefix", { fg = colors.primary_accent, bg = colors.base00 })
    highlight("AvantePromptInputBorder", { fg = colors.primary_accent })
    highlight("DressingInputBorder", { fg = colors.primary_accent })
    highlight("DressingSelectBorder", { fg = colors.primary_accent })

    highlight("NvimTreeNormal", { fg = colors.base05, bg = colors.base00 })
    highlight("NvimTreeCursorLine", { fg = colors.primary_accent, bg = colors.base01, bold = true })
    highlight("NvimTreeEndOfBuffer", { fg = colors.base00, bg = colors.base00 })
    highlight("NvimTreeRootFolder", { fg = colors.base0E, bold = true })
    highlight("NvimTreeFolderIcon", { fg = colors.base0D })
    highlight("NvimTreeFileIcon", { fg = colors.base05 })
    highlight("NvimTreeSpecialFile", { fg = colors.base0A, underline = true })
    highlight("NvimTreeGitDirty", { fg = colors.base0A })
    highlight("NvimTreeGitNew", { fg = colors.base0B })
    highlight("NvimTreeGitDeleted", { fg = colors.base08 })
    highlight("NvimTreeIndentMarker", { fg = colors.base02 })

    highlight("LspReferenceText", { bg = colors.base01 })
    highlight("LspReferenceRead", { bg = colors.base01 })
    highlight("LspReferenceWrite", { bg = colors.base02, bold = true })
    highlight("LspInlayHint", { fg = colors.soft_neutral, bg = colors.base00, italic = true })

    highlight("DiagnosticError", { fg = colors.error })
    highlight("DiagnosticWarn", { fg = colors.warning })
    highlight("DiagnosticInfo", { fg = colors.info })
    highlight("DiagnosticHint", { fg = colors.hint })
    highlight("DiagnosticOk", { fg = colors.ok })
    highlight("DiagnosticVirtualTextError", { fg = colors.error, bg = colors.base00, italic = true })
    highlight("DiagnosticVirtualTextWarn", { fg = colors.warning, bg = colors.base00, italic = true })
    highlight("DiagnosticVirtualTextInfo", { fg = colors.info, bg = colors.base00, italic = true })
    highlight("DiagnosticVirtualTextHint", { fg = colors.hint, bg = colors.base00, italic = true })

    highlight("GitSignsAdd", { fg = colors.ok })
    highlight("GitSignsChange", { fg = colors.signal })
    highlight("GitSignsDelete", { fg = colors.error })


    highlight("IndentBlanklineChar", { fg = colors.base01 })
    highlight("IndentBlanklineContextChar", { fg = colors.soft_neutral })

    highlight("MarkdownHeadingDelimiter", { fg = colors.base09, bold = true })
    highlight("MarkdownH1", { fg = colors.base08, bold = true })
    highlight("MarkdownH2", { fg = colors.base09, bold = true })
    highlight("MarkdownH3", { fg = colors.base0A, bold = true })
    highlight("MarkdownH4", { fg = colors.base0B, bold = true })
    highlight("MarkdownH5", { fg = colors.base0D, bold = true })
    highlight("MarkdownH6", { fg = colors.base0E, bold = true })

    highlight("Cursor", { fg = colors.base00, bg = colors.primary_accent })
    highlight("lCursor", { fg = colors.base00, bg = colors.primary_accent })
    highlight("CursorIM", { fg = colors.base00, bg = colors.primary_accent })
    highlight("TermCursor", { fg = colors.base00, bg = colors.primary_accent })
    highlight("TermCursorNC", { fg = colors.base03, bg = colors.base03 })
end
