-- Rustaceanvim configuration for enhanced Rust development
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
                -- Enable clippy on save
                checkOnSave = {
                    command = 'clippy',
                    extraArgs = { '--all', '--', '-W', 'clippy::all' },
                },
                -- Cargo configuration
                cargo = {
                    allFeatures = true,
                    loadOutDirsFromCheck = true,
                    runBuildScripts = true,
                },
                -- Enable proc macros
                procMacro = {
                    enable = true,
                    ignored = {
                        ['async-trait'] = { 'async_trait' },
                        ['napi-derive'] = { 'napi' },
                        ['async-recursion'] = { 'async_recursion' },
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



-- Configure inlay hints appearance
vim.api.nvim_set_hl(0, 'LspInlayHint', {
    fg = '#7c7c7c',
    bg = 'NONE',
    italic = true,
    bold = false,
})

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
