-- ═══════════════════════════════════════════════════════════════════════════════
-- 🚀 NEOVIM CONFIGURATION LOADER
-- ═══════════════════════════════════════════════════════════════════════════════

-- Early error handling setup to prevent TreeSitter window ID issues
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        -- Set up global error handling for async operations
        local original_schedule = vim.schedule
        vim.schedule = function(fn)
            return original_schedule(function()
                local ok, err = pcall(fn)
                if not ok and not string.match(tostring(err), "Invalid window id") then
                    vim.notify("Scheduled operation error: " .. tostring(err), vim.log.levels.DEBUG)
                end
            end)
        end
    end,
})

-- Core Configuration
require("custom.colors")
DefineColors("catppuccin-mocha")

-- Visual Enhancement Plugins (load early for better experience)
require("custom.plugins.alpha")
do
  local ok, err = pcall(require, "custom.plugins.notify")
  if not ok then
    vim.schedule(function()
      vim.api.nvim_echo({ { "Notify module missing; using default vim.notify", "WarningMsg" } }, false, {})
    end)
  end
end
require("custom.plugins.indent-blankline")
require("custom.plugins.rainbow-delimiters")
require("custom.plugins.colorizer")

-- Plugin Configurations (in logical loading order)
require("custom.plugins.telescope")
require("custom.plugins.treesitter")
require("custom.plugins.mason")
require("custom.plugins.lsp")
require("custom.plugins.cmp")
require("custom.plugins.rust")
require("custom.plugins.nvimtree")
require("custom.plugins.bufferline")
require("custom.plugins.fterm")
require("custom.plugins.fidget")
require("custom.plugins.lualine")
require("custom.plugins.dressing")

-- Built-in Plugin Setup
require('Comment').setup()

-- Keybindings (load last to ensure all plugins are available)
require("custom.remap")
