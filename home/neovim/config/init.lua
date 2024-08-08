-- Floating terminal
require("custom.plugins.fterm")
-- Set options for Telescope
require("custom.plugins.telescope")
-- Set options for Treesitter
require("custom.plugins.treesitter")

-- Setup Harpoon
require("custom.plugins.harpoon").setup()

-- Setup Mason for language server installations
require("custom.plugins.mason")
-- Setup nvim-tree
require("custom.plugins.nvimtree")
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

-- Setup barbecue
require("barbecue").setup()

-- Setup nvim-tree
require("nvim-tree").setup()

-- Setup comments
require('Comment').setup()

-- Setup colors
require("custom.colors")
DefineColors("catppuccin-mocha")

-- Remap keys
require("custom.remap")
