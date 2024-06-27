-- You don't need to set any of these options.
-- IMPORTANT!: this is only a showcase of how you can set default options!
require("telescope").setup {
    extensions = {
        extensions = {
            ["ui-select"] = {}
        },
        file_browser = {
            theme = "ivy",
            -- disables netrw and use telescope-file-browser in its place
            hijack_netrw = true,
            grouped = true,
            depth = 3,
            auto_depth = true,
            layout_config = {
                prompt_position = "top",
                preview_width = 0.3,
            },
            mappings = {
                ["i"] = {
                    -- your custom insert mode mappings
                },
                ["n"] = {
                    -- your custom normal mode mappings
                },
            },
        },
    },
}
-- To get telescope-file-browser loaded and working with telescope,
-- you need to call load_extension, somewhere after setup function:
require("telescope").load_extension "file_browser"

local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
vim.keymap.set('n', '<leader>fg', builtin.git_files, {})
vim.keymap.set('n', '<leader>fw', builtin.live_grep, {})
vim.keymap.set('n', '<leader>ft', builtin.buffers, {})
vim.keymap.set('n', '<leader>fr', function()
    builtin.grep_string({
        search = vim.fn.input("Grep String > ")
    })
end)
vim.keymap.set("n", "<space>fb", function()
    require("telescope").extensions.file_browser.file_browser({ path = "%:p:h", select_buffer = true })
end)
