-- ═══════════════════════════════════════════════════════════════════════════════
-- 📑 BUFFERLINE CONFIGURATION - Pure Buffer Management (Replaces Harpoon)
-- ═══════════════════════════════════════════════════════════════════════════════

local bufferline = require('bufferline')

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
        separator_style = "slant",
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
                text = "📁 File Explorer",
                text_align = "center",
                separator = true
            }
        },
    }
}

-- Catppuccin integration API changed upstream. Try to use it if available,
-- but don't error if the function name differs or the module is absent.
do
    local ok, bl = pcall(require, "catppuccin.groups.integrations.bufferline")
    if ok and bl then
        local get_fn = bl.get or bl.highlights
        if type(get_fn) == "function" then
            setup_opts.highlights = get_fn()
        end
    end
end

bufferline.setup(setup_opts)

-- Note: All keybindings are centralized in keymaps.lua for discoverability via Legendary
-- See: <leader>? to search all keybindings
