-- ═══════════════════════════════════════════════════════════════════════════════
-- 🚀 NEOVIM CONFIGURATION LOADER
-- ═══════════════════════════════════════════════════════════════════════════════

-- Core Configuration
require("custom.colors")
DefineColors("catppuccin-mocha")

-- Visual Enhancement Plugins (load early for better experience)
require("custom.plugins.alpha")
require("custom.plugins.notify")
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
require("custom.plugins.harpoon").setup()
require("custom.plugins.fterm")
require("custom.plugins.fidget")
require("custom.plugins.lualine")
require("custom.plugins.dressing")

-- Built-in Plugin Setup
require('Comment').setup()

-- Keybindings (load last to ensure all plugins are available)
require("custom.remap")
