-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎨 ENHANCED LUALINE CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- Enhanced visual settings for harpoon tabline
local colors = {
    yellow = '#f9e2af',     -- catppuccin yellow
    orange = '#fab387',     -- catppuccin peach
    background = "#1e1e2e", -- catppuccin base
    surface = "#313244",    -- catppuccin surface0
    grey = "#6c7086",       -- catppuccin overlay0
    blue = "#89b4fa",       -- catppuccin blue
    green = "#a6e3a1",      -- catppuccin green
    red = "#f38ba8",        -- catppuccin red
    purple = "#cba6f7",     -- catppuccin mauve
    teal = "#94e2d5",       -- catppuccin teal
}

-- Harpoon styling
vim.api.nvim_set_hl(0, "HarpoonInactive", { fg = colors.grey, bg = colors.background })
vim.api.nvim_set_hl(0, "HarpoonActive", { fg = colors.blue, bg = colors.background, bold = true })
vim.api.nvim_set_hl(0, "HarpoonNumberActive", { fg = colors.yellow, bg = colors.background, bold = true })
vim.api.nvim_set_hl(0, "HarpoonNumberInactive", { fg = colors.orange, bg = colors.background })
vim.api.nvim_set_hl(0, "TabLineFill", { fg = "white", bg = colors.background })

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
            label = '📁 ' .. dir_path
        elseif harpoon_file_path ~= "" then
            label = vim.fn.fnamemodify(harpoon_file_path, ":t")
        end

        label = label ~= "" and label or "󰟢 (empty)"

        if current_file_path == harpoon_file_path then
            contents[index] = string.format("%%#HarpoonNumberActive#%d%%#HarpoonActive# %s ", index, label)
        else
            contents[index] = string.format("%%#HarpoonNumberInactive#%d%%#HarpoonInactive# %s ", index, label)
        end
    end

    return table.concat(contents, "  ")
end

-- Custom components with beautiful icons
local function lsp_status()
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    if #clients == 0 then
        return "󰅚 No LSP"
    end

    local client_names = {}
    for _, client in ipairs(clients) do
        table.insert(client_names, client.name)
    end
    return "󰒋 " .. table.concat(client_names, ", ")
end

local function macro_recording()
    local rec_reg = vim.fn.reg_recording()
    if rec_reg == "" then
        return ""
    else
        return "󰑋 Recording @" .. rec_reg
    end
end

local function get_file_icon()
    local filename = vim.fn.expand('%:t')
    local extension = vim.fn.expand('%:e')

    local file_icons = {
        lua = '󰢱',
        py = '󰌠',
        js = '󰌞',
        ts = '󰛦',
        jsx = '󰜈',
        tsx = '󰜈',
        rs = '󱘗',
        go = '󰟓',
        java = '󰬷',
        cpp = '󰙲',
        c = '󰙱',
        md = '󰍔',
        json = '󰘦',
        yaml = '󰈚',
        yml = '󰈚',
        toml = '󰰔',
        nix = '󱄅',
    }

    return file_icons[extension] or '󰈔'
end

require('lualine').setup {
    options = {
        icons_enabled = true,
        theme = 'catppuccin',
        -- Beautiful powerline separators
        component_separators = { left = '󰿟', right = '󰿟' },
        section_separators = { left = '', right = '' },
        disabled_filetypes = {
            statusline = { 'alpha', 'dashboard', 'NvimTree' },
            winbar = {},
        },
        ignore_focus = {},
        always_divide_middle = true,
        globalstatus = true, -- Single statusline for all windows
        refresh = {
            statusline = 100,
            tabline = 100,
            winbar = 100,
        }
    },
    sections = {
        lualine_a = {
            {
                'mode',
                fmt = function(str)
                    local mode_icons = {
                        ['NORMAL'] = '󰋜 NORMAL',
                        ['INSERT'] = '󰏫 INSERT',
                        ['VISUAL'] = '󰈈 VISUAL',
                        ['V-LINE'] = '󰈈 V-LINE',
                        ['V-BLOCK'] = '󰈈 V-BLOCK',
                        ['COMMAND'] = '󰘳 COMMAND',
                        ['REPLACE'] = '󰛔 REPLACE',
                        ['SELECT'] = '󰒉 SELECT',
                        ['TERMINAL'] = '󰆍 TERMINAL',
                    }
                    return mode_icons[str] or str
                end,
                color = { gui = 'bold' }
            }
        },
        lualine_b = {
            {
                'branch',
                icon = '󰊢',
                color = { fg = colors.purple, gui = 'bold' }
            },
            {
                'diff',
                symbols = {
                    added = '󰐕 ',
                    modified = '󰝤 ',
                    removed = '󰍵 '
                },
                diff_color = {
                    added = { fg = colors.green },
                    modified = { fg = colors.yellow },
                    removed = { fg = colors.red }
                }
            },
            {
                'diagnostics',
                symbols = {
                    error = '󰅚 ',
                    warn = '󰀪 ',
                    info = '󰋽 ',
                    hint = '󰌶 '
                },
                diagnostics_color = {
                    error = { fg = colors.red },
                    warn = { fg = colors.yellow },
                    info = { fg = colors.blue },
                    hint = { fg = colors.teal }
                }
            }
        },
        lualine_c = {
            {
                get_file_icon,
                color = { fg = colors.blue }
            },
            {
                'filename',
                symbols = {
                    modified = '󰷥',
                    readonly = '󰌾',
                    unnamed = '󰟢',
                    newfile = '󰎔',
                },
                color = { gui = 'bold' }
            },
            {
                macro_recording,
                color = { fg = colors.red, gui = 'bold' }
            }
        },
        lualine_x = {
            {
                lsp_status,
                color = { fg = colors.green }
            },
            {
                'encoding',
                icon = '󰉿',
                color = { fg = colors.grey }
            },
            {
                'fileformat',
                symbols = {
                    unix = '󰻀',
                    dos = '󰍲',
                    mac = '󰀵'
                },
                color = { fg = colors.grey }
            },
            {
                'filetype',
                icon_only = false,
                colored = true
            }
        },
        lualine_y = {
            {
                'progress',
                fmt = function(str)
                    return '󰹹 ' .. str
                end,
                color = { fg = colors.purple }
            }
        },
        lualine_z = {
            {
                'location',
                fmt = function(str)
                    return '󰆤 ' .. str
                end,
                color = { gui = 'bold' }
            }
        }
    },
    inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = {
            {
                get_file_icon,
                color = { fg = colors.grey }
            },
            {
                'filename',
                symbols = {
                    modified = '󰷥',
                    readonly = '󰌾',
                    unnamed = '󰟢',
                }
            }
        },
        lualine_x = { 'location' },
        lualine_y = {},
        lualine_z = {}
    },
    tabline = {
        lualine_a = {
            {
                Harpoon_files,
                separator = { left = '', right = '' },
            }
        },
        lualine_b = {},
        lualine_c = {},
        lualine_x = {},
        lualine_y = {},
        lualine_z = {
            {
                'tabs',
                mode = 2, -- Show tab number and name
                symbols = {
                    modified = '󰷥',
                },
                fmt = function(name, context)
                    return context.tabnr .. ' ' .. name
                end
            }
        }
    },
    winbar = {},
    inactive_winbar = {},
    extensions = { "nvim-tree", "mason", "fzf", "trouble" }
}
