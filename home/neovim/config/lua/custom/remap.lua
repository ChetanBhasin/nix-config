-- Set the leader key to space
vim.g.mapleader = " "


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

local legendary = require("legendary")
local filters = require("legendary.filters")

local format = function()
    vim.lsp.buf.format({
        filter = function(filter_client)
            -- Remove tsserver from LSPs available for formatting
            return filter_client.name ~= "tsserver"
        end,
    })
end

local function find_related()
    require("telescope.builtin").find_files({ cwd = vim.fn.expand("%:p:h") })
end

legendary.setup({
    keymaps = {
        {
            "<C-leader>",
            function()
                legendary.find({ filters = { filters.mode("n"), filters.keymaps() } })
            end,
            description = "Show Legendary (normal)",
            mode = "n",
        },
        {
            "<C-Space>",
            function()
                legendary.find({ filters = { filters.mode("v"), filters.keymaps() } })
            end,
            description = "Show Legendary (visual)",
            mode = "v",
        },
        { "<leader>ew", ":e %%<CR>",                          description = "Edit file" },
        { "<leader>es", ":split<CR>",                         description = "Split horizontally" },
        { "<leader>ev", ":vsplit<CR>",                        description = "Split vertically" },
        { "<leader>ff", format,                               description = "Reformat file" },
        -- Telescope
        { "<C-p>",      ":Telescope find_files<CR>",          description = "Search file names" },
        { "<leader>fw", ":Telescope live_grep<CR>",           description = "Search inside files" },
        { "<leader>fr", find_related,                         description = "Find related files" },
        { "gd",         ":Telescope lsp_definitions<CR>",     description = "Search LSP Definitions" },
        { "gr",         ":Telescope lsp_references<CR>",      description = "Search LSP References" },
        { "gi",         ":Telescope lsp_implementations<CR>", description = "Search LSP Implementations" },
        { "[e",         vim.diagnostic.goto_next,             description = "Next diagnostic" },
        { "]e",         vim.diagnostic.goto_prev,             description = "Prev diagnostic" },
        { "<leader>ac", vim.lsp.buf.code_action,              description = "LSP Code Action" },
        { "<leader>rn", vim.lsp.buf.rename,                   description = "LSP Rename" },
        { "K",          vim.lsp.buf.hover,                    description = "LSP Hover" },
        { "gd",         vim.lsp.buf.definition,               description = "LSP Goto Definition" },
        { "gi",         vim.lsp.buf.implementation,           description = "LSP Goto Implementation" },
        { "<leader>f",  ":NvimTreeToggle<CR>",                description = "Toggle NvimTree" },
        { "<leader>ft", ":Telescope buffers<CR>",             description = "Look for buggers" },
        { "<leader>ct", ":%bd|e#<CR>",                        description = "Close except current buffer" },
    },
    functions = {
    },
    autocmds = {
        {
            name = "LspFormatting",
            clear = true,
            {
                "BufWritePre",
                format,
            },
        },
    },
})

-- Use vim keybindings in command mode
vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")
