-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔧 NVIM-CMP COMPLETION CONFIGURATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Completion engine with LuaSnip integration

local cmp_ok, cmp = pcall(require, "cmp")
if not cmp_ok then
    return
end

local luasnip_ok, luasnip = pcall(require, "luasnip")
if not luasnip_ok then
    vim.notify("LuaSnip not found", vim.log.levels.WARN)
    return
end

local lspkind = require("lspkind")

-- Load friendly-snippets
require("luasnip.loaders.from_vscode").lazy_load()

-- LuaSnip configuration
luasnip.config.setup({
    history = true,
    updateevents = "TextChanged,TextChangedI",
    enable_autosnippets = true,
})

-- Helper function for super-tab behavior
local has_words_before = function()
    unpack = unpack or table.unpack
    local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
end

cmp.setup({
    -- Snippet expansion
    snippet = {
        expand = function(args)
            luasnip.lsp_expand(args.body)
        end,
    },

    preselect = cmp.PreselectMode.None,

    completion = {
        completeopt = "menu,menuone,noinsert",
    },

    mapping = cmp.mapping.preset.insert({
        -- Navigation: j goes down, k goes up (vim convention)
        ["<C-j>"] = cmp.mapping.select_next_item(),
        ["<C-k>"] = cmp.mapping.select_prev_item(),

        -- Documentation scrolling
        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),

        -- Trigger completion
        ["<C-Space>"] = cmp.mapping.complete(),

        -- Cancel
        ["<C-e>"] = cmp.mapping.abort(),

        -- Confirm selection
        ["<CR>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Replace,
            select = true,
        }),

        -- Super-Tab: Tab to expand/jump or select next
        ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
                cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
                luasnip.expand_or_jump()
            elseif has_words_before() then
                cmp.complete()
            else
                fallback()
            end
        end, { "i", "s" }),

        -- Shift-Tab: Jump back or select prev
        ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
                cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
                luasnip.jump(-1)
            else
                fallback()
            end
        end, { "i", "s" }),
    }),

    -- Completion sources
    sources = cmp.config.sources({
        { name = "nvim_lsp", keyword_length = 2 },
        { name = "luasnip", keyword_length = 2 },
        { name = "nvim_lua", keyword_length = 2 },
        { name = "treesitter", keyword_length = 2 },
        { name = "path" },
    }, {
        { name = "buffer", keyword_length = 3 },
        { name = "git" },
        { name = "tmux" },
        { name = "zsh" },
        { name = "clippy" },
        { name = "spell" },
    }),

    -- Window styling
    window = {
        completion = cmp.config.window.bordered({
            border = "rounded",
            winhighlight = "Normal:Pmenu,FloatBorder:PmenuBorder,CursorLine:PmenuSel,Search:None",
        }),
        documentation = cmp.config.window.bordered({
            border = "rounded",
            winhighlight = "Normal:Pmenu,FloatBorder:PmenuBorder",
        }),
    },

    -- Formatting with lspkind icons
    formatting = {
        fields = { "kind", "abbr", "menu" },
        format = lspkind.cmp_format({
            mode = "symbol_text",
            maxwidth = 50,
            ellipsis_char = "...",
            before = function(entry, vim_item)
                local menu_icon = {
                    nvim_lsp = "[LSP]",
                    luasnip = "[Snippet]",
                    nvim_lua = "[Lua]",
                    treesitter = "[TS]",
                    buffer = "[Buffer]",
                    path = "[Path]",
                    git = "[Git]",
                    tmux = "[Tmux]",
                    zsh = "[Zsh]",
                    clippy = "[Clippy]",
                    spell = "[Spell]",
                }
                vim_item.menu = menu_icon[entry.source.name] or "[Unknown]"
                return vim_item
            end,
        }),
    },

    -- Experimental features
    experimental = {
        ghost_text = false, -- Disable ghost text (can be distracting)
    },
})

-- Note: Snippet keybindings (<C-l>, <C-h>, <C-e>) are centralized in keymaps.lua
-- for discoverability via Legendary. See: <leader>? to search all keybindings
