require("nvim-tree").setup({
    update_focused_file = {
        enable = true,
        update_root = false,
        ignore_list = {},
    },
})

local function auto_update_path()
    local buf = vim.api.nvim_get_current_buf()
    local bufname = vim.api.nvim_buf_get_name(buf)
    if vim.fn.isdirectory(bufname) or vim.fn.isfile(bufname) then
        require("nvim-tree.api").tree.find_file(vim.fn.expand("%:p"))
    end
end

vim.api.nvim_create_autocmd("BufEnter", { callback = auto_update_path })
vim.api.nvim_create_autocmd("TabEnter", { callback = auto_update_path })
