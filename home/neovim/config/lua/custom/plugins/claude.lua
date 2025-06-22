-- ═══════════════════════════════════════════════════════════════════════════════
-- 🤖 CLAUDE CODE CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Configuration for greggh/claude-code.nvim plugin (available in nixpkgs)
--
-- This plugin is a simple terminal wrapper around Claude Code CLI tool.
-- It provides a single :ClaudeCode command that opens Claude in a terminal.
--
-- User Requirements:
-- 1. Claude terminal on right side, collapsible but not closed
-- 2. No auto-selection of currently open file
-- 3. No auto-start (manual toggle only)
-- 4. Visual file selection capability (handled by Claude CLI itself)
-- 5. No review/edit step for suggestions (handled by Claude CLI itself)
-- ═══════════════════════════════════════════════════════════════════════════════

local claude_config = {
    setup = function()
        -- Load claude-code plugin (available in nixpkgs as claude-code-nvim)
        local ok, claude_code = pcall(require, "claude-code")
        if not ok then
            vim.notify(
                "claude-code plugin not found. Make sure claude-code-nvim is installed via nixpkgs.",
                vim.log.levels.ERROR,
                { title = "Claude Code Setup" }
            )
            return
        end

        -- Configure claude-code with user requirements
        claude_code.setup({
            -- ═══════════════════════════════════════════════════════════════════════════
            -- 🖥️ TERMINAL WINDOW POSITIONING (RIGHT SIDEBAR)
            -- ═══════════════════════════════════════════════════════════════════════════
            window = {
                split_ratio = 0.35,             -- 35% of screen width for right sidebar
                position = "rightbelow vsplit", -- Right vertical split (sidebar)
                enter_insert = true,            -- Enter insert mode when opening
                hide_numbers = true,            -- Hide line numbers in terminal
                hide_signcolumn = true,         -- Hide sign column in terminal
            },

            -- ═══════════════════════════════════════════════════════════════════════════
            -- 🔄 FILE REFRESH SETTINGS
            -- ═══════════════════════════════════════════════════════════════════════════
            refresh = {
                enable = true,             -- Enable file change detection
                updatetime = 100,          -- Update time when Claude is active
                timer_interval = 1000,     -- Check for file changes every second
                show_notifications = true, -- Show notifications when files reload
            },

            -- ═══════════════════════════════════════════════════════════════════════════
            -- 📁 GIT INTEGRATION
            -- ═══════════════════════════════════════════════════════════════════════════
            git = {
                use_git_root = true, -- Set CWD to git root when opening Claude
            },

            -- ═══════════════════════════════════════════════════════════════════════════
            -- 🐚 SHELL SETTINGS
            -- ═══════════════════════════════════════════════════════════════════════════
            shell = {
                separator = '&&',    -- Command separator
                pushd_cmd = 'pushd', -- Directory stack push command
                popd_cmd = 'popd',   -- Directory stack pop command
            },

            -- ═══════════════════════════════════════════════════════════════════════════
            -- 🚀 CLAUDE COMMAND SETTINGS
            -- ═══════════════════════════════════════════════════════════════════════════
            command = "claude",          -- Claude CLI command
            command_variants = {
                continue = "--continue", -- Resume most recent conversation
                resume = "--resume",     -- Interactive conversation picker
                verbose = "--verbose",   -- Enable verbose logging
            },

            -- ═══════════════════════════════════════════════════════════════════════════
            -- ⌨️ KEYMAPS (DISABLE DEFAULTS - WE HANDLE CENTRALLY)
            -- ═══════════════════════════════════════════════════════════════════════════
            keymaps = {
                toggle = {
                    normal = false,       -- Disable default normal mode keymap
                    terminal = false,     -- Disable default terminal mode keymap
                    variants = {
                        continue = false, -- Disable default continue keymap
                        verbose = false,  -- Disable default verbose keymap
                    },
                },
                window_navigation = true, -- Keep window navigation (<C-h/j/k/l>)
                scrolling = true,         -- Keep scrolling keymaps (<C-f/b>)
            },
        })



        vim.notify("Claude Code configured successfully! Use <leader>co to toggle Claude terminal.", vim.log.levels.INFO)
    end
}

-- Initialize Claude configuration
claude_config.setup()

return claude_config
