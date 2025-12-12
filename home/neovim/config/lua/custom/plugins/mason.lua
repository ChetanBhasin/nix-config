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
        "ruff",                  -- Python linter
        "basedpyright",          -- Python language server
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
            -- Python LSPs are configured manually in lsp.lua to avoid duplicates
            if server_name == "basedpyright" or server_name == "pyright" or server_name == "ruff" then
                return
            end
            require("lspconfig")[server_name].setup({
                capabilities = require('cmp_nvim_lsp').default_capabilities(),
            })
        end,
    },
})

-- Proactively uninstall Mason's classic 'pyright' if present to avoid confusion
-- with 'basedpyright'. This will not affect Nix-managed or lspconfig-registered
-- servers and only removes the Mason package if it exists.
pcall(function()
  local registry = require("mason-registry")
  if registry.has_package("pyright") then
    local pkg = registry.get_package("pyright")
    if pkg:is_installed() then
      pkg:uninstall()
      vim.schedule(function()
        vim.notify("Mason: uninstalled 'pyright' to prefer 'basedpyright'", vim.log.levels.INFO)
      end)
    end
  end
end)


-- LSP Diagnostics Options Setup (Neovim 0.11+ API)
vim.diagnostic.config({
    virtual_text = false,
    update_in_insert = true,
    underline = true,
    severity_sort = false,
    float = {
        border = 'rounded',
        source = 'always',
        header = '',
        prefix = '',
    },
    -- Signs configuration using new Neovim 0.11+ API (replaces sign_define)
    signs = {
        text = {
            [vim.diagnostic.severity.ERROR] = '❌',
            [vim.diagnostic.severity.WARN] = '⚠️',
            [vim.diagnostic.severity.HINT] = '💡',
            [vim.diagnostic.severity.INFO] = 'ℹ️',
        },
        numhl = {
            [vim.diagnostic.severity.ERROR] = 'DiagnosticSignError',
            [vim.diagnostic.severity.WARN] = 'DiagnosticSignWarn',
            [vim.diagnostic.severity.HINT] = 'DiagnosticSignHint',
            [vim.diagnostic.severity.INFO] = 'DiagnosticSignInfo',
        },
    },
})

vim.cmd([[
  set signcolumn=yes
]])
