-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎯 NEOVIM BASIC SETTINGS & KEYBINDING SETUP
-- ═══════════════════════════════════════════════════════════════════════════════
-- Basic Neovim settings and reference to centralized keybinding configuration
-- ═══════════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔧 BASIC NEOVIM SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Line numbers enabled
vim.opt.nu = true
vim.opt.relativenumber = true

-- Tab configuration
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Line wrapping
vim.opt.wrap = false

-- File handling
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

-- Search configuration
vim.opt.hlsearch = false
vim.opt.incsearch = true

-- Visual settings
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")
vim.opt.updatetime = 50
vim.opt.colorcolumn = "120"

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎯 LOAD CENTRALIZED KEYBINDING CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- All keybindings are now centralized in keymaps.lua
-- This provides better organization and consistency
require("custom.keymaps")

-- ═══════════════════════════════════════════════════════════════════════════════
-- 📝 NOTES
-- ═══════════════════════════════════════════════════════════════════════════════
--[[

CONFIGURATION STRUCTURE:
═══════════════════════════

📁 lua/custom/
├─ 📄 remap.lua      → Basic settings (this file)
├─ 📄 keymaps.lua    → All keybindings (centralized)
├─ 📁 plugins/
│  ├─ lsp.lua        → LSP configuration
│  ├─ rust.lua       → Rust-specific configuration
│  ├─ telescope.lua  → Telescope configuration
│  └─ ...            → Other plugin configs
└─ 📄 init.lua       → Main loader

All keybindings are documented in keymaps.lua with:
- Consistent formatting
- Clear descriptions
- Logical grouping
- Quick reference guide

--]]
