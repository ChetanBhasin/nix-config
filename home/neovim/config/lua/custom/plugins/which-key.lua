-- ═══════════════════════════════════════════════════════════════════════════════
-- ⌨️ WHICH-KEY CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Displays available keybindings as you type

local ok, wk = pcall(require, "which-key")
if not ok then
    return
end

wk.setup({
    preset = "modern", -- "classic", "modern", or "helix"
    delay = 300, -- Delay before showing popup (ms)
    icons = {
        breadcrumb = "»",
        separator = "➜",
        group = "+",
        ellipsis = "…",
        mappings = true,
        rules = {},
        colors = true,
        keys = {
            Up = " ",
            Down = " ",
            Left = " ",
            Right = " ",
            C = "󰘴 ",
            M = "󰘵 ",
            D = "󰘳 ",
            S = "󰘶 ",
            CR = "󰌑 ",
            Esc = "󱊷 ",
            ScrollWheelDown = "󱕐 ",
            ScrollWheelUp = "󱕑 ",
            NL = "󰌑 ",
            BS = "󰁮",
            Space = "󱁐 ",
            Tab = "󰌒 ",
            F1 = "󱊫",
            F2 = "󱊬",
            F3 = "󱊭",
            F4 = "󱊮",
            F5 = "󱊯",
            F6 = "󱊰",
            F7 = "󱊱",
            F8 = "󱊲",
            F9 = "󱊳",
            F10 = "󱊴",
            F11 = "󱊵",
            F12 = "󱊶",
        },
    },
    win = {
        no_overlap = true,
        border = "rounded",
        padding = { 1, 2 },
        title = true,
        title_pos = "center",
        zindex = 1000,
    },
    layout = {
        width = { min = 20 },
        spacing = 3,
    },
    show_help = true,
    show_keys = true,
    triggers = {
        { "<auto>", mode = "nxsot" },
    },
})

-- Register group names for better organization
wk.add({
    -- Leader key groups
    { "<leader>b", group = "Buffer" },
    { "<leader>c", group = "Code Actions" },
    { "<leader>d", group = "Debug/Diagnostics" },
    { "<leader>e", group = "Edit/Split" },
    { "<leader>f", group = "Find/Files" },
    { "<leader>g", group = "Git" },
    { "<leader>j", group = "Jujutsu" },
    { "<leader>l", group = "LSP" },
    { "<leader>r", group = "Rust/Rename" },
    { "<leader>t", group = "Toggle" },
    { "<leader>x", group = "Trouble" },

    -- Go-to mappings
    { "g", group = "Go to" },
    { "gd", desc = "Definition" },
    { "gD", desc = "Declaration" },
    { "gi", desc = "Implementation" },
    { "go", desc = "Type Definition" },
    { "gr", desc = "References" },
    { "gs", desc = "Signature Help" },

    -- Bracket navigation
    { "[", group = "Previous" },
    { "]", group = "Next" },
})
