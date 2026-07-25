-- Show the active function signature and expected argument while typing.
local signature_ok, signature = pcall(require, "lsp_signature")
if not signature_ok then
    return
end

signature.setup({
    bind = true,
    doc_lines = 0,
    max_height = 6,
    max_width = function()
        local width = math.floor(vim.api.nvim_win_get_width(0) * 0.8)
        return math.min(80, math.max(40, width))
    end,
    wrap = true,
    floating_window = true,
    floating_window_above_cur_line = true,
    floating_window_off_x = 1,
    hint_enable = false,
    handler_opts = {
        border = "rounded",
    },
    always_trigger = false,
    extra_trigger_chars = { "(", "," },
    timer_interval = 100,
})
