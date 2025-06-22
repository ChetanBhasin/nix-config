-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎯 NEOVIM KEYBINDING CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Centralized keybinding configuration with consistent formatting and organization
-- ═══════════════════════════════════════════════════════════════════════════════

-- Set the leader key to space
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔧 UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Helper function for setting keymaps with consistent options
local function keymap(mode, lhs, rhs, opts)
    local options = { noremap = true, silent = true }
    if opts then
        options = vim.tbl_extend('force', options, opts)
    end
    vim.keymap.set(mode, lhs, rhs, options)
end

-- Format function with LSP filtering
local format = function()
    vim.lsp.buf.format({
        filter = function(filter_client)
            -- Remove tsserver from LSPs available for formatting
            return filter_client.name ~= "tsserver"
        end,
    })
end

-- Find files related to current file
local function find_related()
    require("telescope.builtin").find_files({ cwd = vim.fn.expand("%:p:h") })
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🚀 CORE KEYBINDINGS
-- ═══════════════════════════════════════════════════════════════════════════════

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ WINDOW NAVIGATION                                                           │
-- └─────────────────────────────────────────────────────────────────────────────┘
keymap("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
keymap("n", "<C-j>", "<C-w>j", { desc = "Move to bottom window" })
keymap("n", "<C-k>", "<C-w>k", { desc = "Move to top window" })
keymap("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ WINDOW MANAGEMENT                                                           │
-- └─────────────────────────────────────────────────────────────────────────────┘
keymap("n", "<leader>es", ":split<CR>", { desc = "Split horizontally" })
keymap("n", "<leader>ev", ":vsplit<CR>", { desc = "Split vertically" })
keymap("n", "<leader>ew", ":e %%<CR>", { desc = "Edit file in current directory" })

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ BUFFER MANAGEMENT                                                           │
-- └─────────────────────────────────────────────────────────────────────────────┘
keymap("n", "<leader>ft", ":Telescope buffers<CR>", { desc = "List open buffers" })
keymap("n", "<leader>ct", ":%bd|e#<CR>", { desc = "Close all except current buffer" })

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔍 SEARCH & NAVIGATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ TELESCOPE SEARCH                                                            │
-- └─────────────────────────────────────────────────────────────────────────────┘
keymap("n", "<C-p>", ":Telescope find_files<CR>", { desc = "Search file names" })
keymap("n", "<leader>ff", ":Telescope find_files<CR>", { desc = "Find files" })
keymap("n", "<leader>fw", ":Telescope live_grep<CR>", { desc = "Search inside files" })
keymap("n", "<leader>fr", find_related, { desc = "Find related files" })
keymap("n", "<leader>fb", ":Telescope buffers<CR>", { desc = "Find buffers" })
keymap("n", "<leader>fh", ":Telescope help_tags<CR>", { desc = "Find help tags" })
keymap("n", "<leader>fc", ":Telescope commands<CR>", { desc = "Find commands" })
keymap("n", "<leader>fk", ":Telescope keymaps<CR>", { desc = "Find keymaps" })

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🗂️ FILE EXPLORER
-- ═══════════════════════════════════════════════════════════════════════════════

keymap("n", "<leader>f", ":NvimTreeToggle<CR>", { desc = "Toggle file explorer" })
keymap("n", "<leader>nf", ":NvimTreeFindFile<CR>", { desc = "Find current file in explorer" })

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🏹 HARPOON NAVIGATION
-- ═══════════════════════════════════════════════════════════════════════════════

keymap("n", "<leader>ha", function() require('harpoon'):list():add() end, { desc = "Add file to harpoon" })
keymap("n", "<leader>hd", function() require('harpoon'):list():remove() end, { desc = "Remove file from harpoon" })
keymap("n", "<leader>hh", function() require('harpoon').ui:toggle_quick_menu(require('harpoon'):list()) end,
    { desc = "Show harpoon menu" })
keymap("n", "<leader>h1", function() require('harpoon'):list():select(1) end, { desc = "Go to harpoon file 1" })
keymap("n", "<leader>h2", function() require('harpoon'):list():select(2) end, { desc = "Go to harpoon file 2" })
keymap("n", "<leader>h3", function() require('harpoon'):list():select(3) end, { desc = "Go to harpoon file 3" })
keymap("n", "<leader>h4", function() require('harpoon'):list():select(4) end, { desc = "Go to harpoon file 4" })
keymap("n", "<C-S-P>", function() require('harpoon'):list():prev() end, { desc = "Previous harpoon file" })
keymap("n", "<C-S-N>", function() require('harpoon'):list():next() end, { desc = "Next harpoon file" })

-- ═══════════════════════════════════════════════════════════════════════════════
-- 💻 TERMINAL
-- ═══════════════════════════════════════════════════════════════════════════════

keymap("n", "<C-t>", function() require("FTerm").toggle() end, { desc = "Toggle floating terminal" })
keymap("t", "<C-t>", function() require("FTerm").toggle() end, { desc = "Toggle floating terminal" })

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🧠 LSP FUNCTIONALITY
-- ═══════════════════════════════════════════════════════════════════════════════

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ LSP NAVIGATION                                                              │
-- └─────────────────────────────────────────────────────────────────────────────┘
keymap("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
keymap("n", "gD", vim.lsp.buf.declaration, { desc = "Go to declaration" })
keymap("n", "gi", vim.lsp.buf.implementation, { desc = "Go to implementation" })
keymap("n", "go", vim.lsp.buf.type_definition, { desc = "Go to type definition" })
keymap("n", "gr", vim.lsp.buf.references, { desc = "Show references" })
keymap("n", "gs", vim.lsp.buf.signature_help, { desc = "Show signature help" })

-- Alternative telescope-based LSP navigation
keymap("n", "<leader>ld", ":Telescope lsp_definitions<CR>", { desc = "Search LSP definitions" })
keymap("n", "<leader>lr", ":Telescope lsp_references<CR>", { desc = "Search LSP references" })
keymap("n", "<leader>li", ":Telescope lsp_implementations<CR>", { desc = "Search LSP implementations" })
keymap("n", "<leader>ls", ":Telescope lsp_document_symbols<CR>", { desc = "Document symbols" })
keymap("n", "<leader>lw", ":Telescope lsp_workspace_symbols<CR>", { desc = "Workspace symbols" })

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ LSP ACTIONS                                                                 │
-- └─────────────────────────────────────────────────────────────────────────────┘
keymap("n", "K", vim.lsp.buf.hover, { desc = "Show hover information" })
-- Easy way to dismiss floating windows
keymap("n", "<Esc>", function()
    -- Close any floating windows
    for _, win in pairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
            vim.api.nvim_win_close(win, false)
        end
    end
end, { desc = "Close floating windows" })

keymap("n", "<F2>", vim.lsp.buf.rename, { desc = "Rename symbol" })
keymap("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename symbol" })
keymap("n", "<F4>", vim.lsp.buf.code_action, { desc = "Code actions" })
keymap("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code actions" })
keymap("n", "<leader>ac", vim.lsp.buf.code_action, { desc = "Code actions" })

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ FORMATTING                                                                  │
-- └─────────────────────────────────────────────────────────────────────────────┘
-- Note: <C-y> triggers manual completion (changed from <C-Space> to avoid conflicts)
keymap("n", "<F3>", format, { desc = "Format code" })
keymap("x", "<F3>", format, { desc = "Format selection" })
keymap("n", "<leader>fo", format, { desc = "Format code" })

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ DIAGNOSTICS                                                                 │
-- └─────────────────────────────────────────────────────────────────────────────┘
keymap("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
keymap("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
keymap("n", "[e", vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
keymap("n", "]e", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
keymap("n", "<leader>dl", vim.diagnostic.setloclist, { desc = "Diagnostics to location list" })
keymap("n", "<leader>dq", vim.diagnostic.setqflist, { desc = "Diagnostics to quickfix list" })

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ INLAY HINTS                                                                 │
-- └─────────────────────────────────────────────────────────────────────────────┘
keymap("n", "<leader>th", function()
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
end, { desc = "Toggle inlay hints (enabled by default)" })

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🦀 RUST-SPECIFIC KEYBINDINGS
-- ═══════════════════════════════════════════════════════════════════════════════

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ RUST ACTIONS                                                                │
-- └─────────────────────────────────────────────────────────────────────────────┘
keymap("n", "<leader>rr", function() vim.cmd.RustLsp('runnables') end, { desc = "Rust runnables" })
keymap("n", "<leader>rt", function() vim.cmd.RustLsp('testables') end, { desc = "Rust testables" })
keymap("n", "<leader>rd", function() vim.cmd.RustLsp('debuggables') end, { desc = "Rust debuggables" })
keymap("n", "<leader>re", function() vim.cmd.RustLsp('explainError') end, { desc = "Explain Rust error" })
keymap("n", "<leader>rm", function() vim.cmd.RustLsp('expandMacro') end, { desc = "Expand Rust macro" })
keymap("n", "<leader>rp", function() vim.cmd.RustLsp('parentModule') end, { desc = "Go to parent module" })
keymap("n", "<leader>rj", function() vim.cmd.RustLsp('joinLines') end, { desc = "Join lines" })
keymap("n", "<leader>rs", function() vim.cmd.RustLsp('ssr') end, { desc = "Structural search replace" })
keymap("n", "<leader>rc", function() vim.cmd.RustLsp('openCargo') end, { desc = "Open Cargo.toml" })

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎛️ LEGENDARY PLUGIN INTEGRATION
-- ═══════════════════════════════════════════════════════════════════════════════

local legendary = require("legendary")
local filters = require("legendary.filters")

-- Show legendary menu for discovering keybindings
keymap("n", "<C-Space>", function()
    legendary.find({ filters = { filters.mode("n"), filters.keymaps() } })
end, { desc = "Show keybinding menu (normal mode)" })

keymap("v", "<C-Space>", function()
    legendary.find({ filters = { filters.mode("v"), filters.keymaps() } })
end, { desc = "Show keybinding menu (visual mode)" })

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔧 AUTO-FORMATTING ON SAVE
-- ═══════════════════════════════════════════════════════════════════════════════

-- Auto-format on save
vim.api.nvim_create_autocmd("BufWritePre", {
    group = vim.api.nvim_create_augroup("LspFormatting", { clear = true }),
    callback = function()
        format()
    end,
})

-- ═══════════════════════════════════════════════════════════════════════════════
-- 📚 KEYBINDING REFERENCE
-- ═══════════════════════════════════════════════════════════════════════════════
--[[

KEYBINDING QUICK REFERENCE:
═══════════════════════════

🏠 BASIC NAVIGATION:
├─ <C-h/j/k/l>     → Move between windows
├─ <leader>es/ev   → Split horizontal/vertical
└─ <leader>ew      → Edit file in current dir

🔍 SEARCH & FILES:
├─ <C-p>           → Find files
├─ <leader>fw      → Search in files
├─ <leader>fr      → Find related files
├─ <leader>f       → Toggle file explorer
└─ <leader>ft      → List buffers

🏹 HARPOON:
├─ <leader>ha      → Add to harpoon
├─ <leader>hh      → Show harpoon menu
├─ <leader>h1-4    → Go to harpoon file 1-4
└─ <C-S-P/N>       → Previous/Next harpoon

🧠 LSP:
├─ gd/gD           → Go to definition/declaration
├─ gi/go           → Go to implementation/type def
├─ gr/gs           → References/signature help
├─ K               → Hover info
├─ <F2>            → Rename
├─ <F3>            → Format
├─ <F4>            → Code actions
├─ [d/]d           → Previous/Next diagnostic
└─ <leader>th      → Toggle inlay hints (enabled by default)

🦀 RUST:
├─ <leader>rr/rt   → Run/Test
├─ <leader>rd      → Debug
├─ <leader>re      → Explain error
├─ <leader>rm      → Expand macro
└─ <leader>rc      → Open Cargo.toml

💻 TERMINAL:
└─ <C-t>           → Toggle floating terminal

--]]
