-- ═══════════════════════════════════════════════════════════════════════════════
-- 🧠 LSP CONFIGURATION (Neovim 0.11+ native API)
-- ═══════════════════════════════════════════════════════════════════════════════
-- Using vim.lsp.config() and vim.lsp.enable() instead of deprecated lspconfig.setup()

if vim.g._custom_lsp_setup_done then return end
vim.g._custom_lsp_setup_done = true

-- ═══════════════════════════════════════════════════════════════════════════════
-- SHARED CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

local lsp_capabilities = require('cmp_nvim_lsp').default_capabilities()

-- Shared on_attach function for all LSP clients
local on_attach = function(client, bufnr)
    -- Enable inlay hints if supported (using colon syntax for Neovim 0.11+)
    if client:supports_method('textDocument/inlayHint') then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- SERVER CONFIGURATIONS
-- ═══════════════════════════════════════════════════════════════════════════════

-- TypeScript/JavaScript
vim.lsp.config('ts_ls', {
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

-- Python: Ruff (linter) - disable hover to avoid conflict with basedpyright
vim.lsp.config('ruff', {
    capabilities = lsp_capabilities,
    on_attach = function(client, bufnr)
        client.server_capabilities.hoverProvider = false
        on_attach(client, bufnr)
    end,
})

-- Python: BasedPyright (language server)
vim.lsp.config('basedpyright', {
    capabilities = lsp_capabilities,
    on_attach = on_attach,
    settings = {
        basedpyright = {
            analysis = {
                typeCheckingMode = "standard",
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = "openFilesOnly",
                inlayHints = {
                    variableTypes = true,
                    functionReturnTypes = true,
                    callArgumentNames = true,
                },
            },
        },
    },
})

-- Nix with nixd (better than nil_ls)
-- Note: Options configuration is platform-aware (macOS doesn't have /etc/hostname)
local nixd_options = {}

-- Only configure NixOS options on Linux where /etc/hostname exists
if vim.fn.has("unix") == 1 and vim.fn.filereadable("/etc/hostname") == 1 then
    nixd_options.nixos = {
        expr = '(builtins.getFlake ("git+file://" + toString ./.)).nixosConfigurations.${builtins.readFile /etc/hostname}.options',
    }
end

-- Home Manager options (works on both platforms)
nixd_options.home_manager = {
    expr = '(builtins.getFlake ("git+file://" + toString ./.)).homeConfigurations."${builtins.getEnv "USER"}".options',
}

vim.lsp.config('nixd', {
    capabilities = lsp_capabilities,
    on_attach = on_attach,
    settings = {
        nixd = {
            nixpkgs = {
                expr = "import <nixpkgs> { }",
            },
            formatting = {
                command = { "alejandra" },
            },
            options = nixd_options,
        },
    },
})

-- JSON
vim.lsp.config('jsonls', {
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- YAML
vim.lsp.config('yamlls', {
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- Kotlin
vim.lsp.config('kotlin_language_server', {
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- Docker
vim.lsp.config('dockerls', {
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- Lua with enhanced settings
vim.lsp.config('lua_ls', {
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
vim.lsp.config('bashls', {
    capabilities = lsp_capabilities,
    on_attach = on_attach,
})

-- Go language server with inlay hints
vim.lsp.config('gopls', {
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

-- Gleam (conditional - only if available)
if vim.fn.executable('gleam') == 1 then
    vim.lsp.config('gleam', {
        capabilities = lsp_capabilities,
        on_attach = on_attach,
    })
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- ENABLE ALL CONFIGURED SERVERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- Core servers (always enabled)
local servers = {
    'ts_ls',
    'ruff',
    'basedpyright',
    'nixd',
    'jsonls',
    'yamlls',
    'kotlin_language_server',
    'dockerls',
    'lua_ls',
    'bashls',
    'gopls',
}

-- Add gleam if available
if vim.fn.executable('gleam') == 1 then
    table.insert(servers, 'gleam')
end

-- Enable all servers
vim.lsp.enable(servers)

-- Note: Rust setup is handled by rustaceanvim (see rust.lua)

-- ═══════════════════════════════════════════════════════════════════════════════
-- LSP UI CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════

-- Basic completion and diagnostic configuration
vim.opt.completeopt = { 'menuone', 'noselect', 'noinsert' }
vim.opt.shortmess = vim.opt.shortmess + { c = true }
vim.opt.updatetime = 300

-- Fixed column for diagnostics to appear
vim.opt.signcolumn = "yes"

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

-- Note: LspInlayHint highlight is configured in colors.lua for consistency

-- Configure LSP hover window
vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
    border = "rounded",
    focusable = true,
    close_events = { "CursorMoved", "BufLeave", "InsertEnter" },
})
