-- ═══════════════════════════════════════════════════════════════════════════════
-- 🚀 ALPHA DASHBOARD CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

local alpha = require("alpha")
local dashboard = require("alpha.themes.dashboard")

-- Custom ASCII art
dashboard.section.header.val = {
    "                                                     ",
    "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗ ",
    "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║ ",
    "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║ ",
    "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║ ",
    "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║ ",
    "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝ ",
    "                                                     ",
    "           🚀 Welcome to your coding sanctuary       ",
    "                                                     ",
}

-- Custom buttons with beautiful icons
dashboard.section.buttons.val = {
    dashboard.button("e", "󰈔  New file", ":ene <BAR> startinsert <CR>"),
    dashboard.button("f", "󰈞  Find file", ":Telescope find_files <CR>"),
    dashboard.button("r", "󰄉  Recent files", ":Telescope oldfiles <CR>"),
    dashboard.button("g", "󰊄  Find text", ":Telescope live_grep <CR>"),
    dashboard.button("q", "󰗼  Quit", ":qa <CR>"),
}

-- Custom footer with system info
local function footer()
    -- Count Nix-managed plugins by checking loaded packages
    local loaded_plugins = 0
    for name, _ in pairs(package.loaded) do
        if name:match("^[%w%-_]+$") and not name:match("^_") then
            loaded_plugins = loaded_plugins + 1
        end
    end

    local datetime = os.date(" %d-%m-%Y   %H:%M:%S")
    local version = vim.version()
    local nvim_version_info = "   v" .. version.major .. "." .. version.minor .. "." .. version.patch

    return {
        "                                                     ",
        "⚡ Nix-managed configuration" .. "        " .. nvim_version_info,
        "                                                     ",
        "󰃭 " .. datetime,
        "                                                     ",
        "      ❝ Code is poetry written in logic ❞          ",
    }
end

dashboard.section.footer.val = footer()

-- Color customization
dashboard.section.header.opts.hl = "AlphaHeader"
dashboard.section.buttons.opts.hl = "AlphaButtons"
dashboard.section.footer.opts.hl = "AlphaFooter"

-- Custom highlight groups
vim.api.nvim_set_hl(0, "AlphaHeader", { fg = "#83a598", bold = true })
vim.api.nvim_set_hl(0, "AlphaButtons", { fg = "#d3869b" })
vim.api.nvim_set_hl(0, "AlphaFooter", { fg = "#928374", italic = true })

-- Layout configuration
dashboard.config.layout = {
    { type = "padding", val = 2 },
    dashboard.section.header,
    { type = "padding", val = 2 },
    dashboard.section.buttons,
    { type = "padding", val = 1 },
    dashboard.section.footer,
}

-- Disable certain features on dashboard
dashboard.config.opts.noautocmd = true

-- Setup alpha
alpha.setup(dashboard.config)

-- Disable folding on alpha buffer and add TreeSitter safeguards
vim.cmd([[
    autocmd FileType alpha setlocal nofoldenable
]])

-- Add safety measures for alpha buffer window management
vim.api.nvim_create_autocmd("FileType", {
    pattern = "alpha",
    callback = function(event)
        -- Disable TreeSitter for alpha buffers to prevent window ID issues
        vim.b[event.buf].ts_highlight = false
        
        -- Add autocmd to handle alpha buffer closing safely
        vim.api.nvim_create_autocmd("BufLeave", {
            buffer = event.buf,
            callback = function()
                -- Small delay to prevent TreeSitter callback issues
                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(event.buf) then
                        vim.b[event.buf].ts_highlight = false
                    end
                end)
            end,
        })
    end,
})
