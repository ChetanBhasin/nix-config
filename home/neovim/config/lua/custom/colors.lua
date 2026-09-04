-- Luna Comfort: lower-strain surfaces layered onto luna.nvim.
-- The upstream plugin still owns its full colorscheme and integrations; its
-- supported `on_colors` hook receives our softer neutral surface/foreground
-- ladder before highlights are generated. Local highlight overrides below add
-- preferences such as italic comments and per-tier Markdown headings.
--
-- This table mirrors modules/theme/luna.nix.

local colors = {
    -- Softer neutral surfaces and foregrounds, dark → light.
    base00 = "#151515",
    base01 = "#232323",
    base02 = "#30343a",
    base03 = "#858585",
    base04 = "#a8a8a8",
    base05 = "#c7c7c7",
    base06 = "#d8d8dc",
    base07 = "#d8d8dc",
    dim_neutral = "#686868",
    surface = "#303030",
    border = "#454545",
    float_bg = "#2b2b2d",
    -- Accents – Luna's four hues + the diagnostic quartet.
    base08 = "#e08585", -- error / variables / diff removed
    base09 = "#e19067", -- keyword-orange / integers, constants
    base0A = "#d9a35a", -- warning / types / attention
    base0B = "#9eb38e", -- string / success / diff added
    base0C = "#8c9cb8", -- info / regex, escape, support
    base0D = "#75a1c7", -- func / functions, methods, headings
    base0E = "#c4a8d6", -- type / keywords, storage
    base0F = "#b09080", -- hint / deprecated, rare
}

local function highlight(name, value)
    vim.api.nvim_set_hl(0, name, value)
end

function DefineColors()
    vim.o.background = "dark"

    -- Luna keeps ownership of highlight generation and plugin integrations.
    -- Its public on_colors hook swaps only the locally softened neutrals.
    local ok, luna = pcall(require, "luna")
    if ok then
        luna.setup({
            transparent = false,
            accent = 1.0,
            plugins = { all = true, auto = true },
            on_colors = function(palette)
                palette.bg = colors.base00
                palette.bg_alt = colors.base01
                palette.bg_soft = "#292929"
                palette.bg_plum = "#32262c"
                palette.bg_delete = "#35191d"
                palette.surface = colors.surface
                palette.selection = colors.base02
                palette.border = colors.border
                palette.float_bg = colors.float_bg

                palette.grey_warm = colors.dim_neutral
                palette.comment = colors.base03
                palette.grey = "#909090"
                palette.grey_mid = "#9a9a9a"
                palette.grey_light = colors.base04
                palette.grey_pale = "#b8b8b8"
                palette.silver = colors.base05
                palette.fg = colors.base05
                palette.fg_bright = colors.base06
                palette.cream = "#d8cec8"
                palette.black = colors.base00
                palette.white = colors.base07

                palette.cursor_line = { bg = colors.base01 }
                palette.cursor_line_nr = { fg = colors.base05 }
                palette.line_nr = colors.dim_neutral
                palette.git = {
                    add = { fg = palette.ok, bg = "#1b2a20" },
                    delete = { fg = palette.error, bg = palette.bg_delete },
                    change = { fg = palette.signal, bg = "#29231f" },
                    text = { fg = colors.base06, bg = "#4a382e" },
                }
                palette.visual = colors.base02
                palette.float_border = colors.border
            end,
        })
        vim.cmd.colorscheme("luna")
    else
        -- Fall back to base16 if the plugin isn't available (bare checkouts).
        require("base16-colorscheme").setup(colors)
        vim.g.colors_name = "luna"
    end

    -- The overrides below apply on top of Luna's highlight tables. They
    -- exist because we want italicized comments, per-tier markdown headings,
    -- and a slightly warmer LSP inlay-hint palette than Luna ships.
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

    highlight("Visual", { fg = colors.base06, bg = colors.base02 })

    highlight("Folded", { bg = colors.base01, fg = colors.base03 })
    highlight("FoldColumn", { bg = colors.base00, fg = colors.base03 })

    highlight("TelescopeBorder", { fg = colors.base03, bg = colors.base00 })
    highlight("TelescopeSelection", { fg = colors.base06, bg = colors.base02, bold = true })
    highlight("TelescopeMatching", { fg = colors.base09, bold = true })
    highlight("TelescopePromptPrefix", { fg = colors.base0D })

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
    highlight("DiagnosticInfo", { fg = colors.base0C })
    highlight("DiagnosticHint", { fg = colors.base0F })
    highlight("DiagnosticVirtualTextError", { fg = colors.base08, bg = colors.base00, italic = true })
    highlight("DiagnosticVirtualTextWarn", { fg = colors.base0A, bg = colors.base00, italic = true })
    highlight("DiagnosticVirtualTextInfo", { fg = colors.base0C, bg = colors.base00, italic = true })
    highlight("DiagnosticVirtualTextHint", { fg = colors.base0F, bg = colors.base00, italic = true })


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
