-- Set the leader key to space
vim.g.mapleader = " "

vim.keymap.set("n", "<leader>u", vim.cmd.UndotreeToggle)


-- Let's set some basic settings
-- Line numbers enabled
vim.opt.nu = true

-- Tab stops at 4 units
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- We don't want line wrapping
vim.opt.wrap = false

-- We also don't want swap files
vim.opt.swapfile = false

-- Setup for Undotree plugin
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

-- Please don't focus on things that I don't need
vim.opt.hlsearch = false
vim.opt.incsearch = true

-- Use term colors
vim.opt.termguicolors = true

-- Let's have 8 lines unless EOF when we scroll down
vim.opt.scrolloff = 8

-- Use vim keybindings in command mode
vim.keymap.set("n" , "<C-h>", "<C-w>h")
vim.keymap.set("n" , "<C-j>", "<C-w>j")
vim.keymap.set("n" , "<C-k>", "<C-w>k")
vim.keymap.set("n" , "<C-l>", "<C-w>l")
