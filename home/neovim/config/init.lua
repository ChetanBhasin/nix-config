-- ═══════════════════════════════════════════════════════════════════════════════
-- 🚀 NEOVIM CONFIGURATION LOADER
-- ═══════════════════════════════════════════════════════════════════════════════

-- Headless Linux sessions have no pbcopy/wl-copy provider. Use OSC 52 for
-- copies, but serve pastes from a local cache so terminal clipboard reads stay
-- disabled. Explicit terminal paste remains Cmd-v/Ctrl-Shift-v.
if vim.env.ZELLIJ and vim.fn.has("mac") == 0 and not vim.env.DISPLAY and not vim.env.WAYLAND_DISPLAY then
	local osc52 = require("vim.ui.clipboard.osc52")
	local cache = {
		["+"] = { {}, "v" },
		["*"] = { {}, "v" },
	}

	local function copy(reg)
		local send = osc52.copy(reg)
		return function(lines, regtype)
			cache[reg] = { vim.deepcopy(lines), regtype }
			send(lines)
		end
	end

	local function paste(reg)
		return function()
			return cache[reg]
		end
	end

	vim.g.clipboard = {
		name = "OSC 52 copy-only",
		copy = {
			["+"] = copy("+"),
			["*"] = copy("*"),
		},
		paste = {
			["+"] = paste("+"),
			["*"] = paste("*"),
		},
		cache_enabled = 0,
	}
end

-- Share the default register with the system clipboard.
vim.opt.clipboard = "unnamedplus"

-- Plugins such as nvim-colorizer inspect this during setup, so enable true
-- colour before loading any visual plugins.
vim.opt.termguicolors = true

-- Early error handling setup to prevent TreeSitter window ID issues
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		-- Set up global error handling for async operations
		local original_schedule = vim.schedule
		vim.schedule = function(fn)
			return original_schedule(function()
				local ok, err = pcall(fn)
				if not ok and not string.match(tostring(err), "Invalid window id") then
					vim.notify("Scheduled operation error: " .. tostring(err), vim.log.levels.DEBUG)
				end
			end)
		end
	end,
})

-- Core Configuration
require("custom.colors")
DefineColors()

-- Visual Enhancement Plugins (load early for better experience)
require("custom.plugins.alpha")
do
	local ok, err = pcall(require, "custom.plugins.notify")
	if not ok then
		vim.schedule(function()
			vim.api.nvim_echo({ { "Notify module missing; using default vim.notify", "WarningMsg" } }, false, {})
		end)
	end
end
require("custom.plugins.indent-blankline")
require("custom.plugins.rainbow-delimiters")
require("custom.plugins.colorizer")
require("custom.plugins.todo-comments") -- Highlight TODO/FIXME/etc comments

-- Plugin Configurations (in logical loading order)
require("custom.plugins.telescope")
require("custom.plugins.treesitter")
require("custom.plugins.mason")
require("custom.plugins.lsp")
require("custom.plugins.signature")
require("custom.plugins.conform")
require("custom.plugins.lint")
require("custom.plugins.cmp")
require("custom.plugins.autopairs") -- Must load after cmp for integration
require("custom.plugins.rust")
require("custom.plugins.nvimtree")
require("custom.plugins.bufferline")
require("custom.plugins.fterm")
require("custom.plugins.fidget")
require("custom.plugins.lualine")
require("custom.plugins.dressing")
require("custom.plugins.trouble") -- Better diagnostics UI
require("custom.plugins.dap") -- Debug Adapter Protocol
require("custom.plugins.gitsigns") -- Git diff signs in gutter
require("custom.plugins.lazygit") -- Lazygit TUI integration
require("custom.plugins.lazyjj") -- Lazyjj TUI integration (Jujutsu VCS)
require("custom.plugins.which-key") -- Keybinding hints (load late to capture all keymaps)

-- Built-in Plugin Setup
require("Comment").setup()

-- Keybindings (load last to ensure all plugins are available)
require("custom.remap")

-- Multiplexer Integration (must follow the general window-navigation maps)
require("custom.plugins.multiplexer-navigation")
