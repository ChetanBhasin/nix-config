-- Remap keys
require("custom.remap")

-- Import plugin configurations
require("custom.plugins.dressing")
-- Floating terminal
require("custom.plugins.fterm")
-- Set options for Telescope
require("custom.plugins.telescope")
-- Set options for Treesitter
require("custom.plugins.treesitter")

-- Set LSP configuration
require("custom.plugins.lsp")

-- Setup colors
require("custom.colors")
DefineColors("catppuccin-mocha")
