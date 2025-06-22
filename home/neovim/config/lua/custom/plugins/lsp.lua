local lspconfig = require('lspconfig')

local lsp_capabilities = require('cmp_nvim_lsp').default_capabilities()

-- Enhanced on_attach function
local on_attach = function(client, bufnr)
    -- All keybindings are centralized in keymaps.lua
    -- This function only handles LSP-specific setup
end

-- TypeScript/JavaScript setup
lspconfig.ts_ls.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
    settings = {
        typescript = {
            inlayHints = {
                includeInlayParameterNameHints = 'all',
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = true,
                includeInlayVariableTypeHintsWhenTypeMatchesName = false,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
            }
        },
        javascript = {
            inlayHints = {
                includeInlayParameterNameHints = 'all',
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = true,
                includeInlayVariableTypeHintsWhenTypeMatchesName = false,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
            }
        }
    }
})

-- Python setup with type hints
lspconfig.pyright.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- Nix with nixd (better than nil_ls)
lspconfig.nixd.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
    settings = {
        nixd = {
            nixpkgs = {
                expr = "import <nixpkgs> { }",
            },
            formatting = {
                command = { "alejandra" }, -- or nixfmt, nixpkgs-fmt
            },
            options = {
                nixos = {
                    expr =
                    '(builtins.getFlake ("git+file://" + toString ./.)).nixosConfigurations.${builtins.readFile /etc/hostname}.options',
                },
                home_manager = {
                    expr =
                    '(builtins.getFlake ("git+file://" + toString ./.)).homeConfigurations."${builtins.getEnv "USER"}".options',
                },
            },
        },
    },
})

-- JSON
lspconfig.jsonls.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- YAML
lspconfig.yamlls.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- Kotlin
lspconfig.kotlin_language_server.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- Docker
lspconfig.dockerls.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- Lua with enhanced settings
lspconfig.lua_ls.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
    settings = {
        Lua = {
            hint = {
                enable = true,
                setType = false,
                paramType = true,
                paramName = 'Disable',
                semicolon = 'Disable',
                arrayIndex = 'Disable',
            },
        },
    },
})

-- Bash
lspconfig.bashls.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- Gleam (if available)
if vim.fn.executable('gleam') == 1 then
    lspconfig.gleam.setup({
        capabilities = lsp_capabilities,
        on_attach = on_attach,
    })
end

-- Go language server with inlay hints
lspconfig.gopls.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
    settings = {
        gopls = {
            hints = {
                assignVariableTypes = true,
                compositeLiteralFields = true,
                compositeLiteralTypes = true,
                constantValues = true,
                functionTypeParameters = true,
                parameterNames = true,
                rangeVariableTypes = true,
            },
        },
    },
})

-- Rust setup is handled by rustaceanvim (see rust.lua)

-- LSP Settings - Basic completion and diagnostic configuration
vim.opt.completeopt = { 'menuone', 'noselect', 'noinsert' }
vim.opt.shortmess = vim.opt.shortmess + { c = true }
vim.opt.updatetime = 300

-- Fixed column for diagnostics to appear
vim.cmd([[
    set signcolumn=yes
]])

-- Show diagnostic popup on cursor hold
vim.api.nvim_create_autocmd("CursorHold", {
    callback = function()
        vim.diagnostic.open_float(nil, {
            focusable = false,
            close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
            border = 'rounded',
            source = 'always',
            prefix = ' ',
            scope = 'cursor',
        })
    end,
})

-- Configure inlay hints appearance
vim.api.nvim_set_hl(0, 'LspInlayHint', {
    fg = '#6c7086',
    bg = 'NONE',
    italic = true
})

-- Configure LSP hover window
vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
    border = "rounded",
    focusable = true,
    close_events = { "CursorMoved", "BufLeave", "InsertEnter" },
})

-- Single, optimal inlay hints setup
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and client.supports_method('textDocument/inlayHint') then
            vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
        end
    end,
})
