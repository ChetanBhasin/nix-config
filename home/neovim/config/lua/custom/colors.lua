-- Gruvbox Night: a daylight-readable Base16 Gruvbox Dark Hard variant.
-- The palette keeps the hard background, lifts the foreground ladder, and
-- retains subdued accents.

local colors = {
    base00 = "#1d2021",
    base01 = "#282828",
    base02 = "#3c3836",
    base03 = "#aea089",
    base04 = "#bcae94",
    base05 = "#d0c0a0",
    base06 = "#dfcfaa",
    base07 = "#ebdbb2",
    base08 = "#db7e75",
    base09 = "#d58a54",
    base0A = "#c9a257",
    base0B = "#a3ad62",
    base0C = "#7fa98a",
    base0D = "#84a9b2",
    base0E = "#c38da0",
    base0F = "#b9916b",
}

local function highlight(name, value)
    vim.api.nvim_set_hl(0, name, value)
end

function DefineColors()
    vim.o.background = "dark"
    require("base16-colorscheme").setup(colors)
    vim.g.colors_name = "gruvbox-night"

    -- Keep ordinary surfaces quiet and opaque so perceived contrast remains
    -- stable regardless of the terminal or multiplexer behind Neovim.
    highlight("Normal", { fg = colors.base05, bg = colors.base00 })
    highlight("NormalNC", { fg = colors.base04, bg = colors.base00 })
    highlight("NormalFloat", { fg = colors.base05, bg = colors.base01 })
    highlight("SignColumn", { bg = colors.base00 })
    highlight("EndOfBuffer", { fg = colors.base00, bg = colors.base00 })
    highlight("FloatBorder", { fg = colors.base03, bg = colors.base01 })
    highlight("WinSeparator", { fg = colors.base02, bg = colors.base00 })
    highlight("VertSplit", { fg = colors.base02, bg = colors.base00 })

    highlight("Comment", { fg = colors.base03, italic = true })
    highlight("@comment", { link = "Comment" })
    highlight("@lsp.type.comment", { link = "Comment" })

    highlight("Pmenu", { fg = colors.base05, bg = colors.base01 })
    highlight("PmenuSel", { fg = colors.base06, bg = colors.base02, bold = true })
    highlight("LspSignatureActiveParameter", { fg = colors.base06, bg = colors.base02, bold = true })

    highlight("CursorLine", { bg = colors.base01 })
    highlight("CursorLineNr", { fg = colors.base0A, bg = colors.base01, bold = true })
    highlight("LineNr", { fg = colors.base03, bg = colors.base00 })

    highlight("Search", { bg = colors.base0A, fg = colors.base00, bold = true })
    highlight("IncSearch", { bg = colors.base09, fg = colors.base00, bold = true })
    highlight("Visual", { fg = colors.base06, bg = colors.base02 })

    highlight("Folded", { bg = colors.base01, fg = colors.base03 })
    highlight("FoldColumn", { bg = colors.base00, fg = colors.base03 })

    highlight("TelescopeBorder", { fg = colors.base03, bg = colors.base00 })
    highlight("TelescopeSelection", { fg = colors.base06, bg = colors.base02, bold = true })
    highlight("TelescopeMatching", { fg = colors.base09, bold = true })
    highlight("TelescopePromptPrefix", { fg = colors.base0E })

    highlight("NvimTreeNormal", { fg = colors.base05, bg = colors.base00 })
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
    highlight("LspInlayHint", { fg = colors.base03, bg = colors.base00, italic = true })

    highlight("DiagnosticError", { fg = colors.base08 })
    highlight("DiagnosticWarn", { fg = colors.base0A })
    highlight("DiagnosticInfo", { fg = colors.base0D })
    highlight("DiagnosticHint", { fg = colors.base0C })
    highlight("DiagnosticVirtualTextError", { fg = colors.base08, bg = colors.base00, italic = true })
    highlight("DiagnosticVirtualTextWarn", { fg = colors.base0A, bg = colors.base00, italic = true })
    highlight("DiagnosticVirtualTextInfo", { fg = colors.base0D, bg = colors.base00, italic = true })
    highlight("DiagnosticVirtualTextHint", { fg = colors.base0C, bg = colors.base00, italic = true })

    highlight("GitSignsAdd", { fg = colors.base0B })
    highlight("GitSignsChange", { fg = colors.base0A })
    highlight("GitSignsDelete", { fg = colors.base08 })

    highlight("IndentBlanklineChar", { fg = colors.base01 })
    highlight("IndentBlanklineContextChar", { fg = colors.base03 })

    highlight("MarkdownHeadingDelimiter", { fg = colors.base09, bold = true })
    highlight("MarkdownH1", { fg = colors.base08, bold = true })
    highlight("MarkdownH2", { fg = colors.base09, bold = true })
    highlight("MarkdownH3", { fg = colors.base0A, bold = true })
    highlight("MarkdownH4", { fg = colors.base0B, bold = true })
    highlight("MarkdownH5", { fg = colors.base0D, bold = true })
    highlight("MarkdownH6", { fg = colors.base0E, bold = true })

    highlight("TermCursor", { fg = colors.base00, bg = colors.base05 })
    highlight("TermCursorNC", { fg = colors.base03, bg = colors.base03 })
end
