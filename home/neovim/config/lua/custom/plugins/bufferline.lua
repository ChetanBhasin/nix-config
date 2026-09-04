-- ═══════════════════════════════════════════════════════════════════════════════
-- 📑 BUFFERLINE CONFIGURATION - Pure Buffer Management (Replaces Harpoon)
-- ═══════════════════════════════════════════════════════════════════════════════

local bufferline = require('bufferline')

local colors = {
    base00 = "#151515",
    base01 = "#232323",
    base02 = "#30343a",
    base03 = "#858585",
    base04 = "#a8a8a8",
    base05 = "#c7c7c7",
    base06 = "#d8d8dc",
    base0A = "#d9a35a",
    inactive_border = "#454545",
}

-- Build setup table first so we can optionally add highlights
local setup_opts = {
    options = {
        mode = "buffers",
        style_preset = bufferline.style_preset.default,
        themable = true,
        numbers = function(opts)
            -- Show buffer position for pinned buffers
            return opts.ordinal
        end,
        close_command = "bdelete! %d",
        right_mouse_command = "bdelete! %d",
        left_mouse_command = "buffer %d",
        middle_mouse_command = nil,
        indicator = {
            icon = '▎',
            style = 'icon',
        },
        buffer_close_icon = '󰅖',
        modified_icon = '●',
        close_icon = '',
        left_trunc_marker = '',
        right_trunc_marker = '',
        max_name_length = 30,
        max_prefix_length = 15,
        truncate_names = true,
        tab_size = 21,
        diagnostics = "nvim_lsp",
        diagnostics_update_in_insert = false,
        diagnostics_indicator = function(count, level, diagnostics_dict, context)
            local icon = level:match("error") and " " or " "
            return " " .. icon .. count
        end,
        color_icons = true,
        show_buffer_icons = true,
        show_buffer_close_icons = true,
        show_close_icon = true,
        show_tab_indicators = true,
        show_duplicate_prefix = true,
        persist_buffer_sort = true,
        separator_style = "thin",
        enforce_regular_tabs = false,
        always_show_bufferline = true,
        hover = {
            enabled = true,
            delay = 200,
            reveal = { 'close' }
        },
        sort_by = function(buffer_a, buffer_b)
            -- Sort pinned buffers first, then by buffer number
            local a_pinned = buffer_a.pinned
            local b_pinned = buffer_b.pinned

            if a_pinned and not b_pinned then
                return true
            elseif not a_pinned and b_pinned then
                return false
            else
                return buffer_a.id < buffer_b.id
            end
        end,
        custom_filter = function(buf_number, buf_numbers)
            -- Show pinned buffers, current buffer, and modified buffers
            local current_buf = vim.api.nvim_get_current_buf()

            -- Always show current buffer
            if buf_number == current_buf then
                return true
            end

            -- Show if buffer is loaded and has content
            if vim.api.nvim_buf_is_loaded(buf_number) then
                local buf_name = vim.api.nvim_buf_get_name(buf_number)

                -- Show if it has a real file path (not empty or special buffers)
                if buf_name ~= "" and not vim.startswith(buf_name, "term://") then
                    return true
                end
            end

            return false
        end,
        -- Groups disabled to prevent compatibility issues
        -- groups = {},
        offsets = {
            {
                filetype = "NvimTree",
                text = "󰉋 Files",
                text_align = "center",
                separator = true
            }
        },
    },
    highlights = {
        fill = { fg = colors.base03, bg = colors.base00 },
        background = { fg = colors.base03, bg = colors.base00 },
        buffer_visible = { fg = colors.base04, bg = colors.base00 },
        buffer_selected = { fg = colors.base06, bg = colors.base01, bold = true, italic = false },
        separator = { fg = colors.base02, bg = colors.base00 },
        separator_visible = { fg = colors.base02, bg = colors.base00 },
        separator_selected = { fg = colors.base02, bg = colors.base01 },
        indicator_selected = { fg = colors.base0A, bg = colors.base01 },
        close_button = { fg = colors.base03, bg = colors.base00 },
        close_button_visible = { fg = colors.base04, bg = colors.base00 },
        close_button_selected = { fg = colors.base05, bg = colors.base01 },
        modified = { fg = colors.base0A, bg = colors.base00 },
        modified_visible = { fg = colors.base0A, bg = colors.base00 },
        modified_selected = { fg = colors.base0A, bg = colors.base01 },
        offset_separator = { fg = colors.inactive_border, bg = colors.base00 },
    },
}

bufferline.setup(setup_opts)

-- Note: All keybindings are centralized in keymaps.lua for discoverability via Legendary
-- See: <leader>? to search all keybindings
