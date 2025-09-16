-- Mason Setup
require("mason").setup({
    ui = {
        icons = {
            package_installed = "✅",
            package_pending = "⏳",
            package_uninstalled = "️📦",
        },
    }
})
require("mason-lspconfig").setup({
    -- Enable automatic installation of essential language servers
    automatic_installation = true,
    ensure_installed = {
        -- Core language servers
        -- rust_analyzer is handled by rustaceanvim (not Mason)
        "ts_ls",                  -- TypeScript/JavaScript
        "ruff",                -- Python
        "kotlin_language_server", -- Kotlin
        -- nixd is installed via Nix (not available in Mason)
        "jsonls",                 -- JSON
        "yamlls",                 -- YAML
        "lua_ls",                 -- Lua
        "bashls",                 -- Bash
        "gopls",                  -- Go
        "dockerls",               -- Docker
    },
    handlers = {
        -- Default handler for most LSP servers
        function(server_name)
            -- Skip servers that are handled elsewhere
            if server_name == "rust_analyzer" then -- handled by rustaceanvim
                return
            end
            if server_name == "nixd" then -- installed via Nix, configured manually
                return
            end
            require("lspconfig")[server_name].setup({
                capabilities = require('cmp_nvim_lsp').default_capabilities(),
            })
        end,
    },
})


-- LSP Diagnostics Options Setup
local sign = function(opts)
    vim.fn.sign_define(opts.name, {
        texthl = opts.name,
        text = opts.text,
        numhl = ''
    })
end

sign({ name = 'DiagnosticSignError', text = '❌' })
sign({ name = 'DiagnosticSignWarn', text = '⚠️' })
sign({ name = 'DiagnosticSignHint', text = '💡' })
sign({ name = 'DiagnosticSignInfo', text = 'ℹ️' })

vim.diagnostic.config({
    virtual_text = false,
    signs = true,
    update_in_insert = true,
    underline = true,
    severity_sort = false,
    float = {
        border = 'rounded',
        source = 'always',
        header = '',
        prefix = '',
    },
})

vim.cmd([[
  set signcolumn=yes
]])
