-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔧 TROUBLE.NVIM CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Better diagnostics list and quickfix

local ok, trouble = pcall(require, "trouble")
if not ok then
    return
end

trouble.setup({
    auto_close = false, -- Auto close when no items
    auto_open = false, -- Auto open when diagnostics exist
    auto_preview = true, -- Auto preview location
    auto_refresh = true, -- Auto refresh when buffer changes
    auto_jump = false, -- Don't auto jump to first item
    focus = false, -- Don't focus trouble window on open
    restore = true, -- Restore last location in buffer
    follow = true, -- Follow current item
    indent_guides = true, -- Show indent guides
    max_items = 200, -- Max items to show
    multiline = true, -- Multi-line messages
    pinned = false, -- Not pinned by default
    warn_no_results = true, -- Warn when no results
    open_no_results = false, -- Don't open if no results

    -- Window configuration
    win = {
        type = "split",
        relative = "editor",
        position = "bottom",
        size = 10,
    },

    -- Preview window
    preview = {
        type = "main",
        scratch = true,
    },

    -- Throttle refresh for performance
    throttle = {
        refresh = 20,
        update = 10,
        render = 10,
        follow = 100,
        preview = { ms = 100, debounce = true },
    },

    -- Key mappings within trouble window
    keys = {
        ["?"] = "help",
        r = "refresh",
        R = "toggle_refresh",
        q = "close",
        o = "jump_close",
        ["<esc>"] = "cancel",
        ["<cr>"] = "jump",
        ["<2-leftmouse>"] = "jump",
        ["<c-s>"] = "jump_split",
        ["<c-v>"] = "jump_vsplit",
        ["}"] = "next",
        ["]]"] = "next",
        ["{"] = "prev",
        ["[["] = "prev",
        dd = "delete",
        d = { action = "delete", mode = "v" },
        i = "inspect",
        p = "preview",
        P = "toggle_preview",
        zo = "fold_open",
        zO = "fold_open_recursive",
        zc = "fold_close",
        zC = "fold_close_recursive",
        za = "fold_toggle",
        zA = "fold_toggle_recursive",
        zm = "fold_more",
        zM = "fold_close_all",
        zr = "fold_reduce",
        zR = "fold_open_all",
        zx = "fold_update",
        zX = "fold_update_all",
        zn = "fold_disable",
        zN = "fold_enable",
        zi = "fold_toggle_enable",
        gb = { -- example of a custom action that toggles the active view filter
            action = function(view)
                view:filter({ buf = 0 }, { toggle = true })
            end,
            desc = "Toggle Current Buffer Filter",
        },
        s = { -- example of a custom action that toggles the severity
            action = function(view)
                local f = view:get_filter("severity")
                local severity = ((f and f.filter.severity or 0) + 1) % 5
                view:filter({ severity = severity }, {
                    id = "severity",
                    template = "{hl:Title}Filter:{hl} {severity}",
                    del = severity == 0,
                })
            end,
            desc = "Toggle Severity Filter",
        },
    },

    -- Mode configurations
    modes = {
        -- Workspace diagnostics
        diagnostics = {
            mode = "diagnostics",
            preview = {
                type = "split",
                relative = "win",
                position = "right",
                size = 0.4,
            },
        },
        -- LSP references/definitions
        lsp = {
            mode = "lsp",
            win = { position = "bottom" },
        },
        -- Symbols outline
        symbols = {
            mode = "lsp_document_symbols",
            win = { position = "right", size = 0.3 },
        },
    },

    -- Icons
    icons = {
        indent = {
            top = "│ ",
            middle = "├╴",
            last = "└╴",
            fold_open = " ",
            fold_closed = " ",
            ws = "  ",
        },
        folder_closed = " ",
        folder_open = " ",
        kinds = {
            Array = " ",
            Boolean = "󰨙 ",
            Class = " ",
            Constant = "󰏿 ",
            Constructor = " ",
            Enum = " ",
            EnumMember = " ",
            Event = " ",
            Field = " ",
            File = " ",
            Function = "󰊕 ",
            Interface = " ",
            Key = " ",
            Method = "󰊕 ",
            Module = " ",
            Namespace = "󰦮 ",
            Null = " ",
            Number = "󰎠 ",
            Object = " ",
            Operator = " ",
            Package = " ",
            Property = " ",
            String = " ",
            Struct = "󰆼 ",
            TypeParameter = " ",
            Variable = "󰀫 ",
        },
    },
})

-- Note: All keybindings are centralized in keymaps.lua for discoverability via Legendary
-- See: <leader>? to search all keybindings
