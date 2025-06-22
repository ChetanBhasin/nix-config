-- Completion Plugin Setup
local cmp = require 'cmp'
local lspkind = require('lspkind')
cmp.setup({
  -- Enable LSP snippets
  snippet = {
    expand = function(args)
      vim.fn["vsnip#anonymous"](args.body)
    end,
  },
  preselect = cmp.PreselectMode.None,
  completion = {
    completeopt = 'menu,menuone,noinsert',
  },
  mapping = {
    ['<C-j>'] = cmp.mapping.select_prev_item(),
    ['<C-k>'] = cmp.mapping.select_next_item(),
    -- Add tab support
    ['<S-Tab>'] = cmp.mapping.select_prev_item(),
    ['<Tab>'] = cmp.mapping.select_next_item(),
    ['<C-S-f>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-y>'] = cmp.mapping.complete(),
    ['<Esc>'] = cmp.mapping.close(),
    ['<CR>'] = cmp.mapping.confirm({
      behavior = cmp.ConfirmBehavior.Insert,
      select = true,
    })
  },
  -- Completion sources (aligned with Nix configuration)
  sources = {
    { name = 'nvim_lsp',   keyword_length = 3 }, -- from language server
    { name = 'nvim_lua',   keyword_length = 2 }, -- complete neovim's Lua runtime API such vim.lsp.*
    { name = 'vsnip',      keyword_length = 2 }, -- nvim-cmp source for vim-vsnip
    { name = 'treesitter', keyword_length = 2 }, -- treesitter completions
    { name = 'buffer',     keyword_length = 2 }, -- source current buffer
    { name = 'path' },                           -- file path completions
    { name = 'git' },                            -- git completions
    { name = 'tmux' },                           -- tmux completions
    { name = 'zsh' },                            -- zsh completions
    { name = 'clippy' },                         -- rust clippy completions
    { name = 'spell' },                          -- spell check completions
  },
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
  formatting = {
    fields = { 'kind', 'abbr', 'menu' },
    format = lspkind.cmp_format({
      mode = 'symbol_text',
      maxwidth = 50,
      ellipsis_char = '...',
      before = function(entry, vim_item)
        local menu_icon = {
          nvim_lsp = '[LSP]',
          nvim_lua = '[Lua]',
          vsnip = '[Snippet]',
          treesitter = '[TS]',
          buffer = '[Buffer]',
          path = '[Path]',
          git = '[Git]',
          tmux = '[Tmux]',
          zsh = '[Zsh]',
          clippy = '[Clippy]',
          spell = '[Spell]',
        }
        vim_item.menu = menu_icon[entry.source.name] or '[Unknown]'
        return vim_item
      end,
    }),
  },
})
