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

-- Load legendary for keybinding discovery
local legendary = require("legendary")

-- Format function with LSP filtering
local format = function()
    vim.lsp.buf.format({
        filter = function(filter_client)
            -- Remove ts_ls from LSPs available for formatting
            return filter_client.name ~= "ts_ls"
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
-- Note: <leader>ft removed as it duplicates <leader>fb (Find buffers) functionality

-- Note: Buffer closing actions are handled by bufferline.lua (<leader>ba, <leader>bL, <leader>bR)
-- Note: Bufferline keybindings are now handled in bufferline-pure.lua

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
-- 📑 BUFFERLINE NAVIGATION (Replaces Harpoon)
-- ═══════════════════════════════════════════════════════════════════════════════
-- Note: Detailed keybindings are set up in bufferline-pure.lua
-- This section is for reference and legendary integration

legendary.keymaps({
    { "<leader>ha", ":BufferLineTogglePin<CR>", description = "📌 Pin buffer (replaces harpoon add)", mode = "n" },
    { "<leader>hh", ":BufferLinePick<CR>", description = "📋 Pick buffer (replaces harpoon menu)", mode = "n" },
    { "<S-h>", ":BufferLineCyclePrev<CR>", description = "📑 Previous buffer", mode = "n" },
    { "<S-l>", ":BufferLineCycleNext<CR>", description = "📑 Next buffer", mode = "n" },
    { "<leader>ba", ":BufferLineCloseOthers<CR>", description = "🗑️ Close all other buffers", mode = "n" },
    { "<leader>bL", ":BufferLineCloseLeft<CR>", description = "🗑️ Close buffers to the left", mode = "n" },
    { "<leader>bR", ":BufferLineCloseRight<CR>", description = "🗑️ Close buffers to the right", mode = "n" },
    { "<leader>bb", ":BufferLinePick<CR>", description = "📋 Pick buffer", mode = "n" },
})

-- Claude Code legendary integration (centralized with other keybindings)
legendary.keymaps({
    { "<leader>co", claude_toggle, description = "🤖 Toggle Claude (hide/show or start with picker)", mode = "n" },
    { "<leader>cc", ":ClaudeCodeContinue<CR>", description = "🔄 Continue last Claude conversation", mode = "n" },
    { "<leader>cr", ":ClaudeCodeResume<CR>", description = "📋 Resume Claude conversation (picker)", mode = "n" },
    { "<leader>cv", ":ClaudeCodeVerbose<CR>", description = "🔍 Claude Code with verbose output", mode = "n" },
    { "<leader>cq", claude_quit_session, description = "🚪 Quit Claude session (graceful termination)", mode = "n" },
    { "<leader>cn", claude_new_session, description = "🆕 Start new Claude session (ignore existing)", mode = "n" },
    {
        "<leader>ch",
        function()
            print([[
🤖 Claude Code Commands (Available):
───────────────────────────────────
:ClaudeCode         - Toggle Claude terminal
:ClaudeCodeContinue - Continue last conversation
:ClaudeCodeResume   - Resume conversation (picker)
:ClaudeCodeVerbose  - Claude with verbose output

🎯 Keybindings:
──────────────
<leader>co - Toggle Claude terminal
<leader>cc - Continue last conversation
<leader>cr - Resume conversation (picker)
<leader>cv - Verbose mode
<leader>ch - Show this help

💡 Note: File selection, diff handling, etc. are handled
by the Claude CLI itself within the terminal.
]])
        end,
        description = "❓ Show Claude Code help",
        mode = "n"
    },
})

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
-- Note: <leader>ac removed as it duplicates <leader>ca functionality

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
-- Note: [e and ]e removed as they duplicate [d and ]d functionality
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
-- 🤖 CLAUDE AI ASSISTANT
-- ═══════════════════════════════════════════════════════════════════════════════

-- ┌─────────────────────────────────────────────────────────────────────────────┐
-- │ CLAUDE TERMINAL COMMANDS (CUSTOM TOGGLE IMPLEMENTATION)                    │
-- └─────────────────────────────────────────────────────────────────────────────┘
-- Enhanced Claude session management with background persistence
-- Helper function to find Claude terminal buffer (running in background)
local function find_claude_terminal_buffer()
    for _, buf in pairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
            local buf_name = vim.api.nvim_buf_get_name(buf)
            local title_ok, title = pcall(vim.api.nvim_buf_get_var, buf, "term_title")

            if string.match(buf_name:lower(), "claude") or
                (title_ok and title and string.match(title:lower(), "claude")) then
                return buf
            end
        end
    end
    return nil
end

-- Helper function to find window displaying a specific buffer
local function find_window_for_buffer(target_buf)
    for _, win in pairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == target_buf then
            return win
        end
    end
    return nil
end

-- Helper function to show Claude terminal in right sidebar
local function show_claude_terminal_in_sidebar(claude_buf)
    -- Create window in right sidebar with proper positioning
    vim.cmd("rightbelow vsplit")
    local win = vim.api.nvim_get_current_win()

    -- Set the buffer in the new window
    vim.api.nvim_win_set_buf(win, claude_buf)

    -- Configure window size (35% width)
    local total_width = vim.o.columns
    local claude_width = math.floor(total_width * 0.35)
    vim.api.nvim_win_set_width(win, claude_width)

    -- Focus the Claude terminal
    vim.cmd("startinsert")
end

-- Enhanced toggle function: Hide/Show for existing, Resume picker for new
function claude_toggle()
    local claude_buf = find_claude_terminal_buffer()

    if claude_buf then
        -- Claude is running in background, toggle window visibility
        local claude_win = find_window_for_buffer(claude_buf)

        if claude_win then
            -- Claude window is visible → Hide it (keep process running)
            vim.api.nvim_win_close(claude_win, false)
            vim.notify("Claude hidden (running in background)", vim.log.levels.INFO)
        else
            -- Claude is hidden → Show it in sidebar
            show_claude_terminal_in_sidebar(claude_buf)
            vim.notify("Claude shown (resumed background session)", vim.log.levels.INFO)
        end
    else
        -- No Claude session exists → Start with conversation picker
        vim.cmd("ClaudeCodeResume")
        vim.notify("Claude started with conversation picker", vim.log.levels.INFO)
    end
end

-- Gracefully terminate Claude session (manual)
function claude_quit_session()
    local claude_buf = find_claude_terminal_buffer()

    if claude_buf then
        -- Send graceful exit to Claude
        local claude_win = find_window_for_buffer(claude_buf)
        if claude_win then
            -- Focus Claude terminal and send exit command
            vim.api.nvim_set_current_win(claude_win)
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-c>exit<CR>", true, false, true), "n", false)

            -- Wait a moment then close
            vim.defer_fn(function()
                if vim.api.nvim_win_is_valid(claude_win) then
                    vim.api.nvim_win_close(claude_win, false)
                end
            end, 1000)
        else
            -- Claude is hidden, just terminate the buffer
            vim.api.nvim_buf_delete(claude_buf, { force = true })
        end

        vim.notify("Claude session terminated gracefully", vim.log.levels.INFO)
    else
        vim.notify("No Claude session to terminate", vim.log.levels.WARN)
    end
end

-- Start new Claude session (ignore existing)
function claude_new_session()
    -- First terminate existing session if present
    claude_quit_session()

    -- Wait a moment then start fresh
    vim.defer_fn(function()
        vim.cmd("ClaudeCode")
        vim.notify("New Claude session started", vim.log.levels.INFO)
    end, 1500)
end

-- Graceful shutdown when Neovim exits
local function gracefully_terminate_claude_on_exit()
    local claude_buf = find_claude_terminal_buffer()

    if claude_buf then
        -- Try to send graceful exit to Claude
        local claude_win = find_window_for_buffer(claude_buf)
        if claude_win then
            vim.api.nvim_set_current_win(claude_win)
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-c>exit<CR>", true, false, true), "n", false)
        end

        -- Give Claude time to save state
        vim.wait(500)
    end
end

-- Set up graceful shutdown on Neovim exit
vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Gracefully terminate Claude session on Neovim exit",
    callback = gracefully_terminate_claude_on_exit,
})

-- Core Claude keybindings
keymap("n", "<leader>co", claude_toggle, { desc = "🤖 Toggle Claude (hide/show or start with picker)" })
keymap("n", "<leader>cc", ":ClaudeCodeContinue<CR>", { desc = "🔄 Continue last Claude conversation" })
keymap("n", "<leader>cr", ":ClaudeCodeResume<CR>", { desc = "📋 Resume Claude conversation (picker)" })
keymap("n", "<leader>cv", ":ClaudeCodeVerbose<CR>", { desc = "🔍 Claude Code with verbose output" })

-- Enhanced session management
keymap("n", "<leader>cq", claude_quit_session, { desc = "🚪 Quit Claude session (graceful termination)" })
keymap("n", "<leader>cn", claude_new_session, { desc = "🆕 Start new Claude session (ignore existing)" })

-- Terminal mode keybinding to toggle Claude from within
keymap("t", "<leader>co", "<C-\\><C-n>:lua claude_toggle()<CR>", { desc = "🤖 Toggle Claude from within terminal" })

-- Alternative: Simple escape from terminal mode to normal mode (then use <leader>co)
keymap("t", "<C-q>", "<C-\\><C-n>", { desc = "Exit terminal mode to normal mode" })

keymap("n", "<leader>ch", function()
    print([[
🤖 Claude Code - Enhanced Session Management:
═══════════════════════════════════════════

📋 Available Commands:
─────────────────────
:ClaudeCode         - Open new Claude terminal
:ClaudeCodeContinue - Continue last conversation
:ClaudeCodeResume   - Resume conversation (picker)
:ClaudeCodeVerbose  - Claude with verbose output

🎯 Enhanced Keybindings:
───────────────────────
<leader>co - Smart Toggle:
           • First time: Start with conversation picker
           • Existing:   Hide/show Claude (keeps running!)
<leader>cc - Continue last conversation (manual)
<leader>cr - Resume with picker (manual)
<leader>cv - Verbose mode
<leader>cq - Quit Claude session (graceful termination)
<leader>cn - New session (ignore existing)
<leader>ch - Show this help

🔄 Background Persistence:
─────────────────────────
• Claude runs in background when hidden
• Instant toggle response (no startup delay)
• Context and conversation preserved
• Graceful shutdown on Neovim exit

🚪 Usage Patterns:
─────────────────
From normal mode:
• <leader>co - Toggle Claude visibility
• <leader>cq - End Claude session

From terminal mode:
• <leader>co - Toggle Claude from within
• <C-q>      - Exit to normal mode

💡 Claude CLI Commands (within terminal):
────────────────────────────────────────
add file.rs    - Add file to context
add src/       - Add directory
clear          - Clear context
/reset         - Reset conversation
/help          - Claude CLI help
]])
end, { desc = "❓ Show enhanced Claude help" })

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎛️ LEGENDARY PLUGIN INTEGRATION
-- ═══════════════════════════════════════════════════════════════════════════════

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

📑 BUFFERLINE (Replaces Harpoon):
├─ <S-h/l>         → Previous/Next buffer
├─ <leader>ha      → Pin buffer (was harpoon add)
├─ <leader>hh      → Pick buffer (was harpoon menu)
├─ <leader>bp      → Pin/unpin buffer
├─ <leader>bb      → Pick buffer (alternative)
├─ <leader>ba      → Close all other buffers
├─ <leader>bL      → Close buffers to the left
├─ <leader>bR      → Close buffers to the right
└─ Click tabs      → Navigate & close

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

🤖 CLAUDE AI:
├─ <leader>co      → Toggle Claude terminal
├─ <leader>cc      → Continue last conversation
├─ <leader>cr      → Resume conversation (picker)
├─ <leader>cv      → Verbose mode
└─ <leader>ch      → Show Claude help

--]]
