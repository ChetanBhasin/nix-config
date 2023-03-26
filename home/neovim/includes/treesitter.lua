-- Defines a read-write directory for treesitters in nvim's cache dir
local parser_install_dir = vim.fn.stdpath("cache") .. "/treesitters"
vim.fn.mkdir(parser_install_dir, "p")
-- Prevents reinstall of treesitter plugins every boot
vim.opt.runtimepath:append(parser_install_dir)

-- Treesitter Plugin Setup
require('nvim-treesitter.configs').setup {
    ensure_installed = { "lua", "rust", "toml" },
    parser_install_dir = parser_install_dir,
    auto_install = true,
    highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
    },
    ident = { enable = true },
    rainbow = {
        enable = true,
        extended_mode = true,
        max_file_lines = nil,
    }
}

-- Treesitter folding
vim.wo.foldmethod = 'expr'
vim.wo.foldexpr = 'nvim_treesitter#foldexpr()'

function ToggleFolding()
    local foldmethod = vim.wo.foldmethod
    if foldmethod == 'manual' or foldmethod == 'marker' then
        -- If code folding is enabled, disable it
        vim.wo.foldmethod = 'manual'
        vim.wo.foldenable = false
        vim.cmd('normal! zE')
    else
        -- If code folding is disabled, enable it and open all folds
        vim.wo.foldmethod = 'expr'
        vim.wo.foldexpr = 'nvim_treesitter#foldexpr()'
        vim.wo.foldlevel = 99
        vim.wo.foldenable = true
    end
end

vim.api.nvim_set_keymap('n', "<leader>f", ":lua ToggleFolding()<CR>", { noremap = true, silent = true })
