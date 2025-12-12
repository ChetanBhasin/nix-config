-- ═══════════════════════════════════════════════════════════════════════════════
-- 🐛 DAP (Debug Adapter Protocol) CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Debugging support for Python and other languages

local dap_ok, dap = pcall(require, "dap")
if not dap_ok then
    return
end

local dapui_ok, dapui = pcall(require, "dapui")
local dap_python_ok, dap_python = pcall(require, "dap-python")

-- ═══════════════════════════════════════════════════════════════════════════════
-- DAP UI CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

if dapui_ok then
    dapui.setup({
        icons = { expanded = "▾", collapsed = "▸", current_frame = "▸" },
        mappings = {
            expand = { "<CR>", "<2-LeftMouse>" },
            open = "o",
            remove = "d",
            edit = "e",
            repl = "r",
            toggle = "t",
        },
        element_mappings = {},
        expand_lines = true,
        force_buffers = true,
        layouts = {
            {
                elements = {
                    { id = "scopes", size = 0.25 },
                    { id = "breakpoints", size = 0.25 },
                    { id = "stacks", size = 0.25 },
                    { id = "watches", size = 0.25 },
                },
                position = "left",
                size = 40,
            },
            {
                elements = {
                    { id = "repl", size = 0.5 },
                    { id = "console", size = 0.5 },
                },
                position = "bottom",
                size = 10,
            },
        },
        floating = {
            max_height = nil,
            max_width = nil,
            border = "rounded",
            mappings = {
                close = { "q", "<Esc>" },
            },
        },
        controls = {
            enabled = true,
            element = "repl",
            icons = {
                pause = "",
                play = "",
                step_into = "",
                step_over = "",
                step_out = "",
                step_back = "",
                run_last = "",
                terminate = "",
            },
        },
        render = {
            indent = 1,
            max_value_lines = 100,
        },
    })

    -- Automatically open/close DAP UI
    dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
    end
    dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
    end
    dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- PYTHON CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

if dap_python_ok then
    -- Use debugpy from the system (installed via Nix)
    -- This will automatically detect virtual environments
    dap_python.setup("python3")

    -- Custom configurations for Python
    dap_python.test_runner = "pytest"
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- SIGNS CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

vim.fn.sign_define("DapBreakpoint", {
    text = "",
    texthl = "DiagnosticError",
    linehl = "",
    numhl = "",
})
vim.fn.sign_define("DapBreakpointCondition", {
    text = "",
    texthl = "DiagnosticWarn",
    linehl = "",
    numhl = "",
})
vim.fn.sign_define("DapLogPoint", {
    text = "",
    texthl = "DiagnosticInfo",
    linehl = "",
    numhl = "",
})
vim.fn.sign_define("DapStopped", {
    text = "",
    texthl = "DiagnosticOk",
    linehl = "DapStoppedLine",
    numhl = "",
})
vim.fn.sign_define("DapBreakpointRejected", {
    text = "",
    texthl = "DiagnosticError",
    linehl = "",
    numhl = "",
})

-- Highlight for stopped line
vim.api.nvim_set_hl(0, "DapStoppedLine", { bg = "#3d4220" })

-- Note: All keybindings are centralized in keymaps.lua for discoverability via Legendary
-- See: <leader>? to search all keybindings
