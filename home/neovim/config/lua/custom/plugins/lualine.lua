-- define visual settings for harpoon tabline
local yellow = '#DCDCAA'
local yellow_orange = '#D7BA7D'
local background_color = "#282829"
local grey = "#797C91"
local light_blue = "#9CDCFE"
vim.api.nvim_set_hl(0, "HarpoonInactive", { fg = grey, bg = background_color })
vim.api.nvim_set_hl(0, "HarpoonActive", { fg = light_blue, bg = background_color })
vim.api.nvim_set_hl(0, "HarpoonNumberActive", { fg = yellow, bg = background_color })
vim.api.nvim_set_hl(0, "HarpoonNumberInactive", { fg = yellow_orange, bg = background_color })
vim.api.nvim_set_hl(0, "TabLineFill", { fg = "white", bg = background_color })

local harpoon = require('harpoon')

function Harpoon_files()
    local contents = {}
    local marks_length = harpoon:list():length()
    local current_file_path = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
    for index = 1, marks_length do
        local harpoon_file_path = harpoon:list():get(index).value

        local label = ""
        if vim.startswith(harpoon_file_path, "oil") then
            local dir_path = string.sub(harpoon_file_path, 7)
            dir_path = vim.fn.fnamemodify(dir_path, ":.")
            label = '[' .. dir_path .. ']'
        elseif harpoon_file_path ~= "" then
            label = vim.fn.fnamemodify(harpoon_file_path, ":t")
        end

        label = label ~= "" and label or "(empty)"
        if current_file_path == harpoon_file_path then
            contents[index] = string.format("%%#HarpoonActive#%s ", label)
        else
            contents[index] = string.format("%%#HarpoonInactive#%s ", label)
        end
    end

    return table.concat(contents)
end

require('lualine').setup {
    options = {
        icons_enabled = true,
        theme = 'catppuccin',
        component_separators = { left = '', right = '' },
        section_separators = { left = '', right = '' },
        disabled_filetypes = {
            statusline = {},
            winbar = {},
        },
        ignore_focus = {},
        always_divide_middle = true,
        globalstatus = false,
        refresh = {
            statusline = 1000,
            tabline = 1000,
            winbar = 1000,
        }
    },
    sections = {
        lualine_a = { 'mode' },
        lualine_b = { 'branch', 'diff', 'diagnostics' },
        lualine_c = {},
        lualine_x = { 'encoding', 'fileformat', 'filetype' },
        lualine_y = { 'progress' },
        lualine_z = { 'location' }
    },
    inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = { 'filename' },
        lualine_x = { 'location' },
        lualine_y = {},
        lualine_z = {}
    },
    tabline = {
        lualine_a = {
            Harpoon_files,
        },
        lualine_b = {},
        lualine_c = {},
        lualine_x = {},
        lualine_y = {},
        lualine_z = {}
    },
    winbar = {},
    inactive_winbar = {},
    extensions = { "nvim-tree", "mason" }
}
