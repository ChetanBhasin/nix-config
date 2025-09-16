if vim.g._custom_lsp_setup_done then return end
vim.g._custom_lsp_setup_done = true

local lspconfig = require('lspconfig')
local util = require('lspconfig.util')

-- Guard: ensure only one client per server per root_dir
local function unique_root(server_names, base_root)
  local names = {}
  if type(server_names) == 'table' then
    for _, n in ipairs(server_names) do names[n] = true end
  else
    names[server_names] = true
  end
  return function(fname)
    local root = base_root and base_root(fname) or nil
    if not root then return nil end
    for _, client in ipairs(vim.lsp.get_active_clients()) do
      if names[client.name] and client.config and client.config.root_dir == root then
        return nil -- another instance already managing this root
      end
    end
    return root
  end
end

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

-- Python: Ruff (linter)
local ruff_base_root = util.root_pattern('pyproject.toml', 'ruff.toml', '.ruff.toml', '.git')
lspconfig.ruff.setup({
    capabilities = lsp_capabilities,
    on_attach = function(client, bufnr)
        client.server_capabilities.hoverProvider = false
        if on_attach then on_attach(client, bufnr) end
    end,
    single_file_support = false,
    root_dir = unique_root({ 'ruff', 'ruff_lsp' }, ruff_base_root),
})

-- Python: BasedPyright (language server)
local bp_base_root = util.root_pattern('pyproject.toml', 'pyrightconfig.json', 'poetry.lock', 'setup.py', 'setup.cfg', '.git')
lspconfig.basedpyright.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
    single_file_support = false,
    root_dir = unique_root({ 'basedpyright', 'pyright' }, bp_base_root),
    settings = {
        basedpyright = {
            analysis = {
                typeCheckingMode = "standard", -- "off", "basic", "standard", "strict"
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = "openFilesOnly", -- or "workspace"
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
