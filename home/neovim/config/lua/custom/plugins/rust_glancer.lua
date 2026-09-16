-- ═══════════════════════════════════════════════════════════════════════════════
-- 🦀 RUST-GLANCER LSP CONFIGURATION (native vim.lsp, not rustaceanvim)
-- ═══════════════════════════════════════════════════════════════════════════════
-- rust-glancer v0.2.0 reads all configuration from initialization options only
-- (no workspace/configuration support) and does not execute proc macros.
-- init_options schema: crates/lsp/proto/src/config in the rust-glancer repo.

-- rust-glancer expects the LSP workspace folder to be the Cargo workspace root
-- and rejects a member crate's manifest. Walk upward and prefer the outermost
-- Cargo.toml that declares [workspace].
local function rust_glancer_root_dir(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    -- limit = math.huge: without it only the nearest Cargo.toml is returned
    local manifests = vim.fs.find('Cargo.toml', { path = fname, upward = true, limit = math.huge })

    -- manifests is ordered nearest-to-farthest; keep the farthest [workspace] match
    local workspace_root
    for _, manifest in ipairs(manifests) do
        for _, line in ipairs(vim.fn.readfile(manifest)) do
            if line:match('^%[workspace%]') then
                workspace_root = vim.fs.dirname(manifest)
            end
        end
    end

    on_dir(workspace_root or (manifests[1] and vim.fs.dirname(manifests[1])) or vim.fs.dirname(fname))
end

local capabilities = require('cmp_nvim_lsp').default_capabilities()

vim.lsp.config('rust_glancer', {
    cmd = { 'rust-glancer', 'lsp' },
    filetypes = { 'rust' },
    root_dir = rust_glancer_root_dir,
    capabilities = capabilities,
    on_attach = function(client, bufnr)
        if client:supports_method('textDocument/inlayHint') then
            vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end
    end,
    -- Read once at startup; edit these and run :RustGlancerReindex
    init_options = {
        -- cargo check diagnostics (both flags default to false)
        diagnostics = { onStartup = false, onSave = true },
        -- Also valid, left at server defaults:
        -- cargo = { allFeatures = true, noDefaultFeatures = true,
        --           features = { '...' }, target = 'triple',
        --           overrides = { { path = 'firmware', target = 'riscv32imac-unknown-none-elf' } } }
        -- indexing = { performancePreference = 'lower-peak-memory', packageBatchSize = 128 }
        -- cache = { packageResidency = 'all-resident' }  -- default: 'all-offloadable'
    },
})

vim.lsp.enable('rust_glancer')

-- Auto-format Rust files on save via the server (it spawns rustfmt itself)
vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*.rs",
    callback = function(args)
        local bufnr = args.buf
        local client = vim.lsp.get_client_by_name('rust_glancer')
        if client and client:supports_method('textDocument/formatting') then
            vim.lsp.buf.format({
                bufnr = bufnr,
                async = false,
                timeout_ms = 3000,
                filter = function(c)
                    return c.name == 'rust_glancer'
                end,
            })
        end
    end,
})

-- Restart the server to trigger reindex or pick up init_options changes
vim.api.nvim_create_user_command("RustGlancerReindex", function()
    local client = vim.lsp.get_client_by_name('rust_glancer')
    if client then
        client:stop()
    end
    vim.defer_fn(function()
        vim.cmd("LspStart rust_glancer")
    end, 500)
end, { desc = "Restart rust-glancer to trigger reindex" })
