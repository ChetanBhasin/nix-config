-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎨 ENHANCED LUALINE CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- Color scheme for consistent theming
local colors = {
    bg = "#151515",
    bg_alt = "#232323",
    fg = "#c7c7c7",
    fg_bright = "#d8d8dc",
    grey = "#858585",
    grey_light = "#a8a8a8",
    yellow = "#d9a35a",
    blue = "#75a1c7",
    green = "#6fbe80",
    red = "#e08585",
    purple = "#c4a8d6",
    info = "#8c9cb8",
    hint = "#b09080",
}

-- luna.nvim's bundled Lualine theme reads the unmodified upstream palette.
-- Define the same mode mapping locally so Luna Comfort's on_colors overrides
-- also reach the status line.
local function mode_theme(accent_bg)
    return {
        a = { fg = colors.bg, bg = accent_bg },
        b = { fg = colors.fg, bg = colors.bg_alt },
        c = { fg = colors.fg_bright, bg = colors.bg },
    }
end

local luna_comfort = {
    normal = mode_theme(colors.blue),
    insert = mode_theme(colors.purple),
    visual = mode_theme(colors.grey_light),
    replace = mode_theme(colors.grey),
    command = mode_theme(colors.fg),
    inactive = {
        a = { fg = colors.grey, bg = colors.bg_alt },
        b = { fg = colors.grey, bg = colors.bg_alt },
        c = { fg = colors.grey, bg = colors.bg },
    },
}

-- Custom components with beautiful icons
local function lsp_status()
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    if #clients == 0 then
        return "󰅚 No LSP"
    end

    -- Deduplicate names and show counts if attached multiple times
    local counts = {}
    for _, client in ipairs(clients) do
        counts[client.name] = (counts[client.name] or 0) + 1
    end
    local parts = {}
    for name, cnt in pairs(counts) do
        if cnt > 1 then
            table.insert(parts, string.format("%s×%d", name, cnt))
        else
            table.insert(parts, name)
        end
    end
    table.sort(parts)
    return "󰒋 " .. table.concat(parts, ", ")
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
        theme = luna_comfort,
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
                    info = { fg = colors.info },
                    hint = { fg = colors.hint }
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
    tabline = {}, -- Disabled - using bufferline instead
    winbar = {},
    inactive_winbar = {},
    extensions = { "nvim-tree", "mason", "fzf", "trouble" }
}
