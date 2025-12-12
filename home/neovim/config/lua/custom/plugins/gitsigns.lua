-- ═══════════════════════════════════════════════════════════════════════════════
-- 📝 GITSIGNS CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Git diff signs in the gutter (also works with colocated jj repositories)

local ok, gitsigns = pcall(require, "gitsigns")
if not ok then
    return
end

gitsigns.setup({
    -- Sign column configuration
    signs = {
        add = { text = "│" },
        change = { text = "│" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
        untracked = { text = "┆" },
    },

    -- Staged signs (for git staging area - less relevant for jj)
    signs_staged = {
        add = { text = "│" },
        change = { text = "│" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
    },

    -- Display options
    signcolumn = true, -- Toggle with :Gitsigns toggle_signs
    numhl = false, -- Highlight line numbers
    linehl = false, -- Highlight entire lines
    word_diff = false, -- Highlight word diffs inline

    -- Git directory watching
    watch_gitdir = {
        follow_files = true,
    },

    -- Attachment behavior
    auto_attach = true,
    attach_to_untracked = false,

    -- Current line blame (virtual text)
    current_line_blame = false, -- Toggle with :Gitsigns toggle_current_line_blame
    current_line_blame_opts = {
        virt_text = true,
        virt_text_pos = "eol",
        delay = 500,
        ignore_whitespace = false,
    },
    current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",

    -- Performance
    max_file_length = 40000, -- Disable for files longer than this

    -- Preview window
    preview_config = {
        border = "rounded",
        style = "minimal",
        relative = "cursor",
        row = 0,
        col = 1,
    },
})

-- Note: All keybindings are centralized in keymaps.lua for discoverability via Legendary
-- See: <leader>? to search all keybindings
