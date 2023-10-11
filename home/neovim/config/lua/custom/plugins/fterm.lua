require 'FTerm'.setup({
    border     = 'double',
    dimensions = {
        height = 0.9,
        width = 0.9,
    },
})

vim.keymap.set("n", "<c-t>", require("FTerm").toggle)
