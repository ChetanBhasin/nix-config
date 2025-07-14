-- ═══════════════════════════════════════════════════════════════════════════════
-- 🌳 TREESITTER CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- Safe setup with error handling
local status_ok, treesitter = pcall(require, 'nvim-treesitter.configs')
if not status_ok then
    vim.notify("Failed to load nvim-treesitter.configs", vim.log.levels.ERROR)
    return
end

-- Create autocmd to disable treesitter for problematic buffers
vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
    pattern = { "alpha", "dashboard", "NvimTree", "help", "qf", "lspinfo", "mason" },
    callback = function()
        vim.b.ts_highlight = false
    end,
})

-- Add error handler for TreeSitter window issues
vim.api.nvim_create_autocmd("User", {
    pattern = "TSError",
    callback = function()
        vim.notify("TreeSitter error detected - disabling for current buffer", vim.log.levels.WARN)
        vim.b.ts_highlight = false
    end,
})

-- Global error handler for TreeSitter window issues
local original_schedule = vim.schedule
vim.schedule = function(fn)
    original_schedule(function()
        local ok, err = pcall(fn)
        if not ok and string.match(err, "Invalid window id") then
            -- Silently ignore invalid window ID errors from TreeSitter
            return
        elseif not ok then
            error(err)
        end
    end)
end

treesitter.setup {
    -- Autopairs integration
    autopairs = {
        enable = true
    },

    -- Syntax highlighting
    highlight = {
        enable = true,
        -- Disable highlighting for large files and problematic filetypes
        disable = function(lang, buf)
            -- Check file size
            local max_filesize = 100 * 1024 -- 100 KB
            local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
            if ok and stats and stats.size > max_filesize then
                return true
            end

            -- Check for problematic filetypes
            local problematic_filetypes = {
                "help", "alpha", "dashboard", "NvimTree", "neo-tree",
                "Trouble", "trouble", "lazy", "mason",
                "toggleterm", "lazyterm", "qf", "lspinfo"
            }
            local filetype = vim.bo[buf].filetype
            if vim.tbl_contains(problematic_filetypes, filetype) then
                return true
            end

            -- Check buffer type
            local buftype = vim.bo[buf].buftype
            if buftype == "nofile" or buftype == "prompt" or buftype == "popup" or buftype == "terminal" then
                return true
            end

            return false
        end,
        -- Additional vim regex highlighting
        additional_vim_regex_highlighting = false,
        -- Use a custom callback to handle window errors
        use_languagetree = true,
    },

    -- Indentation based on treesitter
    indent = {
        enable = true,
        -- Disable for certain languages that have issues
        disable = { "python", "yaml" }
    },

    -- Incremental selection
    incremental_selection = {
        enable = true,
        keymaps = {
            init_selection = "gnn",
            node_incremental = "grn",
            scope_incremental = "grc",
            node_decremental = "grm",
        },
    },

    -- Text objects
    textobjects = {
        enable = true,
    },
}

-- Rainbow delimiters are now handled by a separate plugin
-- Configuration is in rainbow-delimiters.lua
