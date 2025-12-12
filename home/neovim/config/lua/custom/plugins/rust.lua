-- ═══════════════════════════════════════════════════════════════════════════════
-- 🦀 RUSTACEANVIM CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Optimized Rust configuration to prevent Neovim hanging issues.
-- Several heavy features have been disabled by default for better performance.
--
-- TO RE-ENABLE FEATURES (if needed):
-- - checkOnSave: Set to true and change command to 'clippy' for strict linting
-- - cargo.allFeatures: Set to true for comprehensive feature analysis
-- - cargo.loadOutDirsFromCheck: Set to true for better build script support
-- - cargo.runBuildScripts: Set to true for complex build environments
-- - procMacro.attributes: Set to true for full proc macro analysis
-- ═══════════════════════════════════════════════════════════════════════════════
vim.g.rustaceanvim = {
    -- Plugin configuration
    tools = {
        hover_actions = {
            auto_focus = false,
        },
        float_win_config = {
            border = "rounded",
            focusable = true,
        },
    },
    -- LSP configuration
    server = {
        standalone = true,
        on_attach = function(client, bufnr)
            -- All keybindings are centralized in keymaps.lua
        end,
        default_settings = {
            -- rust-analyzer language server configuration
            ['rust-analyzer'] = {
                -- Enable all the inlay hints
                inlayHints = {
                    bindingModeHints = {
                        enable = false,
                    },
                    chainingHints = {
                        enable = true,
                    },
                    closingBraceHints = {
                        enable = true,
                        minLines = 25,
                    },
                    closureReturnTypeHints = {
                        enable = 'never',
                    },
                    lifetimeElisionHints = {
                        enable = 'never',
                        useParameterNames = false,
                    },
                    maxLength = 25,
                    parameterHints = {
                        enable = true,
                    },
                    reborrowHints = {
                        enable = 'never',
                    },
                    renderColons = true,
                    typeHints = {
                        enable = true,
                        hideClosureInitialization = false,
                        hideNamedConstructor = false,
                    },
                },
                -- Lens settings for additional context
                lens = {
                    enable = true,
                    debug = {
                        enable = true,
                    },
                    implementations = {
                        enable = true,
                    },
                    run = {
                        enable = true,
                    },
                    methodReferences = {
                        enable = true,
                    },
                    references = {
                        adt = {
                            enable = true,
                        },
                        enumVariant = {
                            enable = true,
                        },
                        method = {
                            enable = true,
                        },
                        trait = {
                            enable = true,
                        },
                    },
                },
                -- Optimize check-on-save to reduce hanging issues
                checkOnSave = false,  -- Disabled by default to prevent hanging
                check = {
                    command = 'check',  -- Use 'check' instead of 'clippy' for speed
                    extraArgs = { '--message-format=json' },
                },
                -- Optimized cargo configuration to reduce load times
                cargo = {
                    allFeatures = false,  -- Disabled to reduce analysis time
                    loadOutDirsFromCheck = false,  -- Disabled to prevent hanging
                    runBuildScripts = false,  -- Disabled to prevent hanging on complex builds
                    noDefaultFeatures = false,
                },
                -- Optimize proc macros to reduce analysis overhead
                procMacro = {
                    enable = true,
                    attributes = {
                        enable = true,  -- Enable attribute macro expansion
                    },
                },
                -- Type information on hover
                hover = {
                    actions = {
                        enable = true,
                        implementations = {
                            enable = true,
                        },
                        references = {
                            enable = true,
                        },
                        run = {
                            enable = true,
                        },
                        debug = {
                            enable = true,
                        },
                    },
                },
                -- Completion settings
                completion = {
                    callable = {
                        snippets = 'fill_arguments',
                    },
                },
                -- Diagnostics
                diagnostics = {
                    enable = true,
                    experimental = {
                        enable = true,
                    },
                },
            },
        },
    },
    -- DAP configuration for debugging
    dap = {
        adapter = {
            type = 'executable',
            command = 'lldb-vscode',
            name = 'rt_lldb',
        },
    },
}


-- Note: LspInlayHint highlight is configured in colors.lua for consistency

-- Additional Rust-specific settings
vim.api.nvim_create_autocmd("FileType", {
    pattern = "rust",
    callback = function()
        -- Show function signatures while typing
        vim.opt_local.signcolumn = "yes"
        -- Better completion experience
        vim.opt_local.completeopt = { 'menuone', 'noselect', 'noinsert' }
    end,
})

-- Auto-format Rust files on save using rust-analyzer (rustfmt)
vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*.rs",
    callback = function(args)
        local bufnr = args.buf
        -- Only format with rust-analyzer to ensure rustfmt is used
        local clients = vim.lsp.get_clients({ bufnr = bufnr })
        local has_ra = false
        for _, c in ipairs(clients) do
            if c.name == "rust_analyzer" or c.name == "rust-analyzer" then
                has_ra = c.supports_method("textDocument/formatting")
                break
            end
        end
        if has_ra then
            vim.lsp.buf.format({
                bufnr = bufnr,
                async = false,
                timeout_ms = 3000,
                filter = function(c)
                    return c.name == "rust_analyzer" or c.name == "rust-analyzer"
                end,
            })
        end
    end,
})
