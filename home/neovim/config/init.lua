-- Remap keys
require("custom.remap")

-- Floating terminal
require("custom.plugins.fterm")
-- Set options for Telescope
require("custom.plugins.telescope")
-- Set options for Treesitter
require("custom.plugins.treesitter")

-- Setup Mason for language server installations
require("custom.plugins.mason")
-- Set LSP configuration
require("custom.plugins.lsp")

-- Setup Fidget
require("custom.plugins.fidget")

-- Setup Lualine
require("custom.plugins.lualine")

-- Import plugin configurations
require("custom.plugins.dressing")

-- Setup cmp
require("custom.plugins.cmp")

-- Setup colors
require("custom.colors")
DefineColors("catppuccin-mocha")
