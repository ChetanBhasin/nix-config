local lspconfig = require('lspconfig')

local lsp_capabilities = require('cmp_nvim_lsp').default_capabilities()

lspconfig.tsserver.setup({
    capabilities = lsp_capabilities,
})
lspconfig.pyright.setup({
    capabilities = lsp_capabilities,
})
lspconfig.rnix.setup({
    capabilities = lsp_capabilities,
})
lspconfig.yamlls.setup({
    capabilities = lsp_capabilities,
})
lspconfig.dockerls.setup({
    capabilities = lsp_capabilities,
})
lspconfig.lua_ls.setup({
    capabilities = lsp_capabilities,
})
lspconfig.bashls.setup({
    capabilities = lsp_capabilities,
})
lspconfig.tsserver.setup({
    capabilities = lsp_capabilities,
})
lspconfig.gleam.setup({
    capabilities = lsp_capabilities,
})
lspconfig.rust_analyzer.setup {
    capabilities = lsp_capabilities,
}

-- LSP Settings
vim.api.nvim_create_autocmd('LspAttach', {
    desc = 'LSP actions',
    callback = function()
        local bufmap = function(mode, lhs, rhs)
            local opts = { buffer = true }
            vim.keymap.set(mode, lhs, rhs, opts)
        end
    end
})

--Set completeopt to have a better completion experience
-- :help completeopt
-- menuone: popup even when there's only one match
-- noinsert: Do not insert text until a selection is made
-- noselect: Do not select, force to select one from the menu
-- shortness: avoid showing extra messages when using completion
-- updatetime: set updatetime for CursorHold
vim.opt.completeopt = { 'menuone', 'noselect', 'noinsert' }
vim.opt.shortmess = vim.opt.shortmess + { c = true }
vim.api.nvim_set_option('updatetime', 300)

-- Fixed column for diagnostics to appear
-- Show autodiagnostic popup on cursor hover_range
-- Goto previous / next diagnostic warning / error
-- Show inlay_hints more frequently
vim.cmd([[
    set signcolumn=yes
    autocmd CursorHold * lua vim.diagnostic.open_float(nil, { focusable = false })
]])
