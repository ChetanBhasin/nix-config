-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔭 TELESCOPE CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

local telescope = require("telescope")
local actions = require("telescope.actions")

telescope.setup({
    defaults = {
        -- Layout configuration
        layout_strategy = "horizontal",
        layout_config = {
            horizontal = {
                prompt_position = "top",
                preview_width = 0.55,
                results_width = 0.8,
            },
            vertical = {
                mirror = false,
            },
            width = 0.87,
            height = 0.80,
            preview_cutoff = 120,
        },
        sorting_strategy = "ascending",

        -- Appearance
        prompt_prefix = "   ",
        selection_caret = "  ",
        entry_prefix = "  ",
        border = true,
        borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },

        -- File ignore patterns
        file_ignore_patterns = {
            "node_modules",
            ".git/",
            "target/",
            "dist/",
            "build/",
            "%.lock",
        },

        -- Mappings
        mappings = {
            i = {
                ["<C-j>"] = actions.move_selection_next,
                ["<C-k>"] = actions.move_selection_previous,
                ["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
                ["<Esc>"] = actions.close,
                ["<C-u>"] = false, -- Clear prompt instead of scroll
            },
            n = {
                ["q"] = actions.close,
            },
        },

        -- Performance
        path_display = { "truncate" },
        winblend = 0,
        color_devicons = true,
        set_env = { ["COLORTERM"] = "truecolor" },
    },

    pickers = {
        find_files = {
            hidden = true,
            find_command = { "rg", "--files", "--hidden", "--glob", "!.git/*" },
        },
        live_grep = {
            additional_args = function()
                return { "--hidden", "--glob", "!.git/*" }
            end,
        },
        buffers = {
            show_all_buffers = true,
            sort_lastused = true,
            mappings = {
                i = {
                    ["<C-d>"] = actions.delete_buffer,
                },
            },
        },
    },

    extensions = {
        ["ui-select"] = {
            require("telescope.themes").get_dropdown({
                -- Configuration for ui-select
            }),
        },
        fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
        },
    },
})

-- Load extensions
telescope.load_extension("ui-select")

-- Load fzf if available (installed via Nix)
local ok, _ = pcall(telescope.load_extension, "fzf")
if not ok then
    vim.schedule(function()
        vim.notify("telescope-fzf-native not available", vim.log.levels.DEBUG)
    end)
end
