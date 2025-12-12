-- ═══════════════════════════════════════════════════════════════════════════════
-- ✅ TODO-COMMENTS CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Highlight and search TODO, FIXME, BUG, etc. comments

local ok, todo = pcall(require, "todo-comments")
if not ok then
    return
end

todo.setup({
    signs = true, -- Show icons in the sign column
    sign_priority = 8, -- Sign priority

    -- Keywords with custom icons and colors
    keywords = {
        FIX = {
            icon = " ",
            color = "error",
            alt = { "FIXME", "BUG", "FIXIT", "ISSUE" },
        },
        TODO = { icon = " ", color = "info" },
        HACK = { icon = " ", color = "warning" },
        WARN = { icon = " ", color = "warning", alt = { "WARNING", "XXX" } },
        PERF = { icon = " ", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
        NOTE = { icon = " ", color = "hint", alt = { "INFO" } },
        TEST = { icon = "⏲ ", color = "test", alt = { "TESTING", "PASSED", "FAILED" } },
    },

    -- GUI style for keywords
    gui_style = {
        fg = "NONE",
        bg = "BOLD",
    },

    -- Merging with defaults
    merge_keywords = true,

    -- Highlighting configuration
    highlight = {
        multiline = true, -- Enable multiline support
        multiline_pattern = "^.", -- Pattern for multiline
        multiline_context = 10, -- Extra lines to highlight
        before = "", -- "fg" or "bg" or empty
        keyword = "wide", -- "fg", "bg", "wide", "wide_bg", "wide_fg" or empty
        after = "fg", -- "fg" or "bg" or empty
        pattern = [[.*<(KEYWORDS)\s*:]], -- Pattern for highlighting
        comments_only = true, -- Only highlight in comments (uses treesitter)
        max_line_len = 400, -- Ignore lines longer than this
        exclude = {}, -- Filetypes to exclude
    },

    -- Colors matching catppuccin theme
    colors = {
        error = { "DiagnosticError", "ErrorMsg", "#f38ba8" },
        warning = { "DiagnosticWarn", "WarningMsg", "#f9e2af" },
        info = { "DiagnosticInfo", "#89dceb" },
        hint = { "DiagnosticHint", "#a6e3a1" },
        default = { "Identifier", "#cba6f7" },
        test = { "Identifier", "#fab387" },
    },

    -- Search configuration
    search = {
        command = "rg",
        args = {
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
        },
        pattern = [[\b(KEYWORDS):]], -- ripgrep regex
    },
})

-- Note: All keybindings are centralized in keymaps.lua for discoverability via Legendary
-- See: <leader>? to search all keybindings
