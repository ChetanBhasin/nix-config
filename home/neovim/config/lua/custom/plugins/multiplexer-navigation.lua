-- Seamless navigation between Neovim windows and tmux/Zellij panes.

local function present(value)
	return value ~= nil and value ~= ""
end

local multiplexer = false
if present(vim.env.ZELLIJ) then
	multiplexer = "zellij"
elseif present(vim.env.TMUX) then
	multiplexer = "tmux"
end

local ok, smart_splits = pcall(require, "smart-splits")

local function save_then(callback)
	return function(...)
		vim.cmd("silent! update")
		return callback(...)
	end
end

local function set_navigation_maps(moves, previous)
	local opts = { silent = true }

	vim.keymap.set(
		"n",
		"<C-h>",
		moves.left,
		vim.tbl_extend("force", opts, { desc = "Navigate left (vim/multiplexer)" })
	)
	vim.keymap.set(
		"n",
		"<C-j>",
		moves.down,
		vim.tbl_extend("force", opts, { desc = "Navigate down (vim/multiplexer)" })
	)
	vim.keymap.set("n", "<C-k>", moves.up, vim.tbl_extend("force", opts, { desc = "Navigate up (vim/multiplexer)" }))
	vim.keymap.set(
		"n",
		"<C-l>",
		moves.right,
		vim.tbl_extend("force", opts, { desc = "Navigate right (vim/multiplexer)" })
	)
	vim.keymap.set("n", "<C-\\>", previous, vim.tbl_extend("force", opts, { desc = "Navigate to previous pane" }))
end

if not ok then
	-- The exported Home Manager module allows multiplexer integration to be
	-- disabled. Keep ordinary Neovim window navigation available in that case.
	set_navigation_maps(
		{
			left = save_then(function()
				vim.cmd("wincmd h")
			end),
			down = save_then(function()
				vim.cmd("wincmd j")
			end),
			up = save_then(function()
				vim.cmd("wincmd k")
			end),
			right = save_then(function()
				vim.cmd("wincmd l")
			end),
		},
		save_then(function()
			vim.cmd("wincmd p")
		end)
	)
	return
end

smart_splits.setup({
	multiplexer_integration = multiplexer,
	at_edge = "stop",
	zellij_move_focus_or_tab = false,
	-- smart-splits can query tmux zoom state, but Zellij does not expose it to
	-- this integration.
	disable_multiplexer_nav_when_zoomed = true,
})

local function previous_pane()
	if #vim.api.nvim_tabpage_list_wins(0) > 1 then
		smart_splits.move_cursor_previous()
		return
	end

	local command
	if multiplexer == "zellij" then
		-- Zellij 0.44 fallback; use focus-last-pane in 0.45 for exact last-active behavior.
		command = { "zellij", "action", "focus-previous-pane" }
	elseif multiplexer == "tmux" then
		command = { "tmux", "select-pane", "-l" }
	end

	if command then
		vim.fn.jobstart(command, { detach = true })
	end
end

set_navigation_maps({
	left = save_then(smart_splits.move_cursor_left),
	down = save_then(smart_splits.move_cursor_down),
	up = save_then(smart_splits.move_cursor_up),
	right = save_then(smart_splits.move_cursor_right),
}, save_then(previous_pane))
