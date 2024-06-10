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
lspconfig.jsonls.setup({
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

        -- Displays hover information about the symbol under the cursorlsp
        bufmap('n', '<Leader>lh', '<cmd>lua vim.lsp.buf.hover()<cr>')

        -- Format the code
        bufmap('n', '<Leader>lf', '<cmd>lua vim.lsp.buf.format()<cr>')

        -- Jump to the definition
        bufmap('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>')

        -- Jump to declaration
        bufmap('n', 'gc', '<cmd>lua vim.lsp.buf.declaration()<cr>')

        -- Lists all the implementations for the symbol under the cursor
        bufmap('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<cr>')

        -- Jumps to the definition of the type symbol
        bufmap('n', 'gt', '<cmd>lua vim.lsp.buf.type_definition()<cr>')

        -- Lists all the references
        bufmap('n', 'gr', '<cmd>lua vim.lsp.buf.references()<cr>')

        -- Displays a function's signature information
        bufmap('n', '<Leader>ls', '<cmd>lua vim.lsp.buf.signature_help()<cr>')

        -- Renames all references to the symbol under the cursor
        bufmap('n', '<Leader>lr', '<cmd>lua vim.lsp.buf.rename()<cr>')

        -- Selects a code action available at the current cursor position
        bufmap('n', '<Leader>la', '<cmd>lua vim.lsp.buf.code_action()<cr>')

        -- Show diagnostics in a floating window
        bufmap('n', '<Leader>ld', '<cmd>lua vim.diagnostic.open_float()<cr>')

        -- Move to the previous diagnostic
        bufmap('n', '[d', '<cmd>lua vim.diagnostic.goto_prev()<cr>')

        -- Move to the next diagnostic
        bufmap('n', ']d', '<cmd>lua vim.diagnostic.goto_next()<cr>')
    end
})

--Set completeopt to have a better completion experience
-- :help completeopt
-- menuone: popup even when there's only one match
-- noinsert: Do not insert text until a selection is made
-- noselect: Do not select, force to select one from the menu
-- shortness: avoid showing extra messages when using completion
-- updatetime: set updatetime for CursorHold
vim.opt.completeopt = {'menuone', 'noselect', 'noinsert'}
vim.opt.shortmess = vim.opt.shortmess + { c = true}
vim.api.nvim_set_option('updatetime', 300) 

-- Fixed column for diagnostics to appear
-- Show autodiagnostic popup on cursor hover_range
-- Goto previous / next diagnostic warning / error 
-- Show inlay_hints more frequently 
vim.cmd([[
    set signcolumn=yes
    autocmd CursorHold * lua vim.diagnostic.open_float(nil, { focusable = false })
]])

