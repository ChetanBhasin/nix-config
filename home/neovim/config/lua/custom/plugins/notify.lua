-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔔 NVIM-NOTIFY CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

local notify = require("notify")

notify.setup({
    -- Animation style
    stages = "fade_in_slide_out",

    -- Function called when a new window is opened
    on_open = function(win)
        vim.api.nvim_win_set_config(win, { zindex = 100 })
    end,

    -- Function called when a window is closed
    on_close = function(win)
        -- Optional cleanup
    end,

    -- Render function
    render = "default",

    -- Default timeout for notifications
    timeout = 3000,

    -- Max number of columns for messages
    max_width = 50,

    -- Max number of lines for a message
    max_height = 10,

    -- Background colour
    background_colour = "#000000",

    -- Minimum width for notification windows
    minimum_width = 30,

    -- Icons for the different levels
    icons = {
        ERROR = "󰅚",
        WARN = "󰀪",
        INFO = "󰋽",
        DEBUG = "󰃤",
        TRACE = "󰌶",
    },

    -- Level configuration
    level = vim.log.levels.INFO, -- Show INFO and above

    -- Top-down or bottom-up
    top_down = true,

    -- Time to keep notifications after they've been dismissed
    fps = 30,
})

-- Replace the default notify function
vim.notify = notify

-- Custom highlight groups for better integration with catppuccin
vim.api.nvim_set_hl(0, "NotifyERRORBorder", { fg = "#f38ba8" })
vim.api.nvim_set_hl(0, "NotifyWARNBorder", { fg = "#f9e2af" })
vim.api.nvim_set_hl(0, "NotifyINFOBorder", { fg = "#89b4fa" })
vim.api.nvim_set_hl(0, "NotifyDEBUGBorder", { fg = "#6c7086" })
vim.api.nvim_set_hl(0, "NotifyTRACEBorder", { fg = "#cba6f7" })

vim.api.nvim_set_hl(0, "NotifyERRORIcon", { fg = "#f38ba8" })
vim.api.nvim_set_hl(0, "NotifyWARNIcon", { fg = "#f9e2af" })
vim.api.nvim_set_hl(0, "NotifyINFOIcon", { fg = "#89b4fa" })
vim.api.nvim_set_hl(0, "NotifyDEBUGIcon", { fg = "#6c7086" })
vim.api.nvim_set_hl(0, "NotifyTRACEIcon", { fg = "#cba6f7" })

vim.api.nvim_set_hl(0, "NotifyERRORTitle", { fg = "#f38ba8", bold = true })
vim.api.nvim_set_hl(0, "NotifyWARNTitle", { fg = "#f9e2af", bold = true })
vim.api.nvim_set_hl(0, "NotifyINFOTitle", { fg = "#89b4fa", bold = true })
vim.api.nvim_set_hl(0, "NotifyDEBUGTitle", { fg = "#6c7086", bold = true })
vim.api.nvim_set_hl(0, "NotifyTRACETitle", { fg = "#cba6f7", bold = true })

-- Custom notification function for better UX
local function custom_notify(message, level, opts)
    opts = opts or {}
    opts.title = opts.title or "Neovim"
    notify(message, level, opts)
end

-- Export for use in other modules
return {
    notify = custom_notify,
    setup = notify.setup,
}
