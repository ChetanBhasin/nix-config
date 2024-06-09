require 'FTerm'.setup({
    border     = 'double',
    dimensions = {
        height = 0.8,
        width = 0.8,
    },
})

vim.keymap.set("n", "<c-t>", require("FTerm").toggle)
