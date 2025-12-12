-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎯 NEOVIM KEYBINDING CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- ALL keybindings are defined here using Legendary for full discoverability.
-- Press <leader>? to search all keybindings.
-- ═══════════════════════════════════════════════════════════════════════════════

-- Set the leader key to space
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔧 UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Enhanced format function with better error handling and feedback
local format = function()
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    local formatting_clients = {}

    for _, client in pairs(clients) do
        if client.supports_method("textDocument/formatting") and client.name ~= "ts_ls" then
            table.insert(formatting_clients, client.name)
        end
    end

    if #formatting_clients == 0 then
        vim.notify("No LSP clients support formatting for this buffer", vim.log.levels.WARN)
        return
    end

    vim.notify("Formatting with: " .. table.concat(formatting_clients, ", "), vim.log.levels.INFO)

    local ok, err = pcall(function()
        vim.lsp.buf.format({
            timeout_ms = 3000,
            async = false,
            filter = function(filter_client)
                return filter_client.name ~= "ts_ls"
            end,
        })
    end)

    if not ok then
        vim.notify("Formatting failed: " .. tostring(err), vim.log.levels.ERROR)
    else
        vim.notify("Formatting completed successfully", vim.log.levels.INFO)
    end
end

-- Async format function for non-blocking formatting
local format_async = function()
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    local formatting_clients = {}

    for _, client in pairs(clients) do
        if client.supports_method("textDocument/formatting") and client.name ~= "ts_ls" then
            table.insert(formatting_clients, client.name)
        end
    end

    if #formatting_clients == 0 then
        vim.notify("No LSP clients support formatting for this buffer", vim.log.levels.WARN)
        return
    end

    vim.notify("Formatting asynchronously with: " .. table.concat(formatting_clients, ", "), vim.log.levels.INFO)

    vim.lsp.buf.format({
        timeout_ms = 5000,
        async = true,
        filter = function(filter_client)
            return filter_client.name ~= "ts_ls"
        end,
    })
end

-- Find files related to current file
local function find_related()
    require("telescope.builtin").find_files({ cwd = vim.fn.expand("%:p:h") })
end

-- Close floating windows helper
local function close_floating_windows()
    for _, win in pairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
            vim.api.nvim_win_close(win, false)
        end
    end
end

-- Toggle inlay hints
local function toggle_inlay_hints()
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎹 LEGENDARY SETUP - Single Source of Truth for ALL Keybindings
-- ═══════════════════════════════════════════════════════════════════════════════

local legendary = require("legendary")

legendary.setup({
    -- Include keymaps from which-key.nvim
    extensions = {
        which_key = {
            auto_register = true,
        },
    },
    -- Sorting
    sort = {
        most_recent_first = true,
        user_items_first = true,
    },
})

-- ═══════════════════════════════════════════════════════════════════════════════
-- 📋 ALL KEYBINDINGS (Registered with Legendary for Discoverability)
-- ═══════════════════════════════════════════════════════════════════════════════

legendary.keymaps({
    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ WINDOW NAVIGATION                                                       │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<C-h>", "<C-w>h", description = "Move to left window", mode = "n" },
    { "<C-j>", "<C-w>j", description = "Move to bottom window", mode = "n" },
    { "<C-k>", "<C-w>k", description = "Move to top window", mode = "n" },
    { "<C-l>", "<C-w>l", description = "Move to right window", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ WINDOW MANAGEMENT                                                       │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<leader>es", ":split<CR>", description = "Split horizontally", mode = "n" },
    { "<leader>ev", ":vsplit<CR>", description = "Split vertically", mode = "n" },
    { "<leader>ew", ":e %%<CR>", description = "Edit file in current directory", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ COMMAND PALETTE                                                         │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<C-p>", function() legendary.find() end, description = "Command palette (Legendary)", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ TELESCOPE SEARCH                                                        │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<leader>ff", ":Telescope find_files<CR>", description = "Find files", mode = "n" },
    { "<leader>fw", ":Telescope live_grep<CR>", description = "Search inside files (grep)", mode = "n" },
    { "<leader>fr", find_related, description = "Find related files in same directory", mode = "n" },
    { "<leader>fb", ":Telescope buffers<CR>", description = "Find buffers", mode = "n" },
    { "<leader>fh", ":Telescope help_tags<CR>", description = "Find help tags", mode = "n" },
    { "<leader>fc", ":Telescope commands<CR>", description = "Find commands", mode = "n" },
    { "<leader>fk", ":Telescope keymaps<CR>", description = "Find keymaps", mode = "n" },
    { "<leader>?", function() legendary.find() end, description = "Search all keybindings (Legendary)", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ FILE EXPLORER                                                           │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<leader>e", ":NvimTreeToggle<CR>", description = "Toggle file explorer", mode = "n" },
    { "<leader>nf", ":NvimTreeFindFile<CR>", description = "Find current file in explorer", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ BUFFERLINE / BUFFER MANAGEMENT                                          │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<S-h>", ":BufferLineCyclePrev<CR>", description = "Previous buffer", mode = "n" },
    { "<S-l>", ":BufferLineCycleNext<CR>", description = "Next buffer", mode = "n" },
    { "<leader>bp", ":BufferLineTogglePin<CR>", description = "Pin/unpin buffer", mode = "n" },
    { "<leader>bb", ":BufferLinePick<CR>", description = "Pick buffer", mode = "n" },
    { "<leader>ba", ":BufferLineCloseOthers<CR>", description = "Close all other buffers", mode = "n" },
    { "<leader>bL", ":BufferLineCloseLeft<CR>", description = "Close buffers to the left", mode = "n" },
    { "<leader>bR", ":BufferLineCloseRight<CR>", description = "Close buffers to the right", mode = "n" },
    { "<leader>bmh", ":BufferLineMovePrev<CR>", description = "Move buffer left", mode = "n" },
    { "<leader>bml", ":BufferLineMoveNext<CR>", description = "Move buffer right", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ TERMINAL                                                                │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<C-t>", function() require("FTerm").toggle() end, description = "Toggle floating terminal", mode = { "n", "t" } },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ LSP NAVIGATION                                                          │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "gd", vim.lsp.buf.definition, description = "Go to definition", mode = "n" },
    { "gD", vim.lsp.buf.declaration, description = "Go to declaration", mode = "n" },
    { "gi", vim.lsp.buf.implementation, description = "Go to implementation", mode = "n" },
    { "go", vim.lsp.buf.type_definition, description = "Go to type definition", mode = "n" },
    { "gr", vim.lsp.buf.references, description = "Show references", mode = "n" },
    { "gs", vim.lsp.buf.signature_help, description = "Show signature help", mode = "n" },
    { "<leader>ld", ":Telescope lsp_definitions<CR>", description = "Search LSP definitions", mode = "n" },
    { "<leader>lr", ":Telescope lsp_references<CR>", description = "Search LSP references", mode = "n" },
    { "<leader>li", ":Telescope lsp_implementations<CR>", description = "Search LSP implementations", mode = "n" },
    { "<leader>ls", ":Telescope lsp_document_symbols<CR>", description = "Document symbols", mode = "n" },
    { "<leader>lw", ":Telescope lsp_workspace_symbols<CR>", description = "Workspace symbols", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ LSP ACTIONS                                                             │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "K", vim.lsp.buf.hover, description = "Show hover information", mode = "n" },
    { "<Esc>", close_floating_windows, description = "Close floating windows", mode = "n" },
    { "<leader>rn", vim.lsp.buf.rename, description = "Rename symbol", mode = "n" },
    { "<leader>ca", vim.lsp.buf.code_action, description = "Code actions", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ FORMATTING                                                              │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<leader>fo", format, description = "Format code (sync)", mode = { "n", "x" } },
    { "<leader>fa", format_async, description = "Format code (async)", mode = { "n", "x" } },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ DIAGNOSTICS                                                             │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "[d", vim.diagnostic.goto_prev, description = "Previous diagnostic", mode = "n" },
    { "]d", vim.diagnostic.goto_next, description = "Next diagnostic", mode = "n" },
    { "<leader>dL", vim.diagnostic.setloclist, description = "Diagnostics to location list", mode = "n" },
    { "<leader>dQ", vim.diagnostic.setqflist, description = "Diagnostics to quickfix list", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ INLAY HINTS                                                             │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<leader>th", toggle_inlay_hints, description = "Toggle inlay hints", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ TROUBLE (Diagnostics UI)                                                │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", description = "Trouble: Workspace diagnostics", mode = "n" },
    { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", description = "Trouble: Buffer diagnostics", mode = "n" },
    { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>", description = "Trouble: Symbols outline", mode = "n" },
    { "<leader>xl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", description = "Trouble: LSP definitions/references", mode = "n" },
    { "<leader>xL", "<cmd>Trouble loclist toggle<cr>", description = "Trouble: Location list", mode = "n" },
    { "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", description = "Trouble: Quickfix list", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ TODO COMMENTS                                                           │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "]t", function() require("todo-comments").jump_next() end, description = "Next TODO comment", mode = "n" },
    { "[t", function() require("todo-comments").jump_prev() end, description = "Previous TODO comment", mode = "n" },
    { "]T", function() require("todo-comments").jump_next({ keywords = { "ERROR", "WARNING" } }) end, description = "Next error/warning comment", mode = "n" },
    { "[T", function() require("todo-comments").jump_prev({ keywords = { "ERROR", "WARNING" } }) end, description = "Previous error/warning comment", mode = "n" },
    { "<leader>ft", "<cmd>TodoTelescope<cr>", description = "Find all TODOs", mode = "n" },
    { "<leader>fT", "<cmd>TodoTelescope keywords=TODO,FIX,FIXME<cr>", description = "Find TODO/FIX comments", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ DEBUGGING (DAP)                                                         │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<leader>db", function() require("dap").toggle_breakpoint() end, description = "Debug: Toggle breakpoint", mode = "n" },
    { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, description = "Debug: Conditional breakpoint", mode = "n" },
    { "<leader>dp", function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: ")) end, description = "Debug: Log point", mode = "n" },
    { "<leader>dc", function() require("dap").continue() end, description = "Debug: Continue", mode = "n" },
    { "<leader>di", function() require("dap").step_into() end, description = "Debug: Step into", mode = "n" },
    { "<leader>do", function() require("dap").step_over() end, description = "Debug: Step over", mode = "n" },
    { "<leader>dO", function() require("dap").step_out() end, description = "Debug: Step out", mode = "n" },
    { "<leader>dr", function() require("dap").repl.open() end, description = "Debug: Open REPL", mode = "n" },
    { "<leader>dl", function() require("dap").run_last() end, description = "Debug: Run last", mode = "n" },
    { "<leader>dt", function() require("dap").terminate() end, description = "Debug: Terminate", mode = "n" },
    { "<leader>du", function() require("dapui").toggle() end, description = "Debug: Toggle UI", mode = "n" },
    { "<leader>de", function() require("dapui").eval() end, description = "Debug: Evaluate expression", mode = { "n", "v" } },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ PYTHON DEBUGGING                                                        │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<leader>dpm", function() require("dap-python").test_method() end, description = "Debug: Python test method", mode = "n" },
    { "<leader>dpc", function() require("dap-python").test_class() end, description = "Debug: Python test class", mode = "n" },
    { "<leader>dps", function() require("dap-python").debug_selection() end, description = "Debug: Python selection", mode = "v" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ RUST                                                                    │
    -- └─────────────────────────────────────────────────────────────────────────┘
    { "<leader>rr", function() vim.cmd.RustLsp('runnables') end, description = "Rust: Runnables", mode = "n" },
    { "<leader>rt", function() vim.cmd.RustLsp('testables') end, description = "Rust: Testables", mode = "n" },
    { "<leader>rd", function() vim.cmd.RustLsp('debuggables') end, description = "Rust: Debuggables", mode = "n" },
    { "<leader>re", function() vim.cmd.RustLsp('explainError') end, description = "Rust: Explain error", mode = "n" },
    { "<leader>rm", function() vim.cmd.RustLsp('expandMacro') end, description = "Rust: Expand macro", mode = "n" },
    { "<leader>rp", function() vim.cmd.RustLsp('parentModule') end, description = "Rust: Go to parent module", mode = "n" },
    { "<leader>rj", function() vim.cmd.RustLsp('joinLines') end, description = "Rust: Join lines", mode = "n" },
    { "<leader>rs", function() vim.cmd.RustLsp('ssr') end, description = "Rust: Structural search replace", mode = "n" },
    { "<leader>rc", function() vim.cmd.RustLsp('openCargo') end, description = "Rust: Open Cargo.toml", mode = "n" },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ VERSION CONTROL (Git/Jujutsu)                                           │
    -- └─────────────────────────────────────────────────────────────────────────┘
    -- Lazygit
    { "<leader>gg", "<cmd>LazyGit<cr>", description = "Git: Open LazyGit", mode = "n" },
    { "<leader>gf", "<cmd>LazyGitCurrentFile<cr>", description = "Git: LazyGit for current file", mode = "n" },
    { "<leader>gl", "<cmd>LazyGitFilter<cr>", description = "Git: LazyGit log (commits)", mode = "n" },

    -- Lazyjj (Jujutsu)
    { "<leader>jj", "<cmd>LazyJJ<cr>", description = "Jujutsu: Open LazyJJ", mode = "n" },

    -- Gitsigns: Hunk navigation
    {
        "]c",
        function()
            if vim.wo.diff then return "]c" end
            vim.schedule(function() require("gitsigns").next_hunk() end)
            return "<Ignore>"
        end,
        description = "Git: Next hunk",
        mode = "n",
        opts = { expr = true },
    },
    {
        "[c",
        function()
            if vim.wo.diff then return "[c" end
            vim.schedule(function() require("gitsigns").prev_hunk() end)
            return "<Ignore>"
        end,
        description = "Git: Previous hunk",
        mode = "n",
        opts = { expr = true },
    },

    -- Gitsigns: Staging
    { "<leader>gs", function() require("gitsigns").stage_hunk() end, description = "Git: Stage hunk", mode = "n" },
    { "<leader>gs", function() require("gitsigns").stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, description = "Git: Stage hunk (visual)", mode = "v" },
    { "<leader>gS", function() require("gitsigns").stage_buffer() end, description = "Git: Stage buffer", mode = "n" },
    { "<leader>gu", function() require("gitsigns").undo_stage_hunk() end, description = "Git: Undo stage hunk", mode = "n" },

    -- Gitsigns: Reset
    { "<leader>gr", function() require("gitsigns").reset_hunk() end, description = "Git: Reset hunk", mode = "n" },
    { "<leader>gr", function() require("gitsigns").reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, description = "Git: Reset hunk (visual)", mode = "v" },
    { "<leader>gR", function() require("gitsigns").reset_buffer() end, description = "Git: Reset buffer", mode = "n" },

    -- Gitsigns: Preview & Blame
    { "<leader>gp", function() require("gitsigns").preview_hunk() end, description = "Git: Preview hunk", mode = "n" },
    { "<leader>gb", function() require("gitsigns").blame_line({ full = true }) end, description = "Git: Blame line", mode = "n" },
    { "<leader>gB", function() require("gitsigns").toggle_current_line_blame() end, description = "Git: Toggle line blame", mode = "n" },

    -- Gitsigns: Diff
    { "<leader>gd", function() require("gitsigns").diffthis() end, description = "Git: Diff this", mode = "n" },
    { "<leader>gD", function() require("gitsigns").diffthis("~") end, description = "Git: Diff this ~", mode = "n" },

    -- Gitsigns: Text object (select hunk)
    { "ih", ":<C-U>Gitsigns select_hunk<CR>", description = "Git: Select hunk (text object)", mode = { "o", "x" } },

    -- ┌─────────────────────────────────────────────────────────────────────────┐
    -- │ SNIPPETS (LuaSnip)                                                      │
    -- └─────────────────────────────────────────────────────────────────────────┘
    {
        "<C-l>",
        function()
            local ls = require("luasnip")
            if ls.expand_or_jumpable() then ls.expand_or_jump() end
        end,
        description = "Snippet: Expand or jump forward",
        mode = { "i", "s" },
    },
    {
        "<C-h>",
        function()
            local ls = require("luasnip")
            if ls.jumpable(-1) then ls.jump(-1) end
        end,
        description = "Snippet: Jump backward",
        mode = { "i", "s" },
    },
    {
        "<C-e>",
        function()
            local ls = require("luasnip")
            if ls.choice_active() then ls.change_choice(1) end
        end,
        description = "Snippet: Change choice",
        mode = { "i", "s" },
    },
})

-- ═══════════════════════════════════════════════════════════════════════════════
-- 📚 KEYBINDING QUICK REFERENCE
-- ═══════════════════════════════════════════════════════════════════════════════
--[[

Press <C-p> or <leader>? to search ALL keybindings interactively!

CATEGORIES:
═══════════════════════════
  <leader>f   → Find/Search (Telescope)
  <leader>e   → File explorer
  <leader>b   → Buffer management
  <leader>g   → Git (gitsigns, lazygit)
  <leader>j   → Jujutsu (lazyjj)
  <leader>l   → LSP navigation
  <leader>d   → Debugging (DAP)
  <leader>x   → Trouble diagnostics
  <leader>r   → Rust / Rename
  <leader>c   → Code actions
  <leader>t   → Toggles
  g           → Go to (LSP)
  [/]         → Previous/Next navigation

QUICK ACCESS:
═══════════════════════════
  <C-p>       → Command palette (Legendary)
  <C-t>       → Terminal
  K           → Hover docs
  <leader>ff  → Find files
  <leader>fw  → Search in files (grep)
  <leader>gg  → Open LazyGit
  <leader>jj  → Open LazyJJ (Jujutsu)
  <leader>rn  → Rename symbol
  <leader>fo  → Format code
  <leader>ca  → Code actions
  <leader>dc  → Debug continue

--]]
