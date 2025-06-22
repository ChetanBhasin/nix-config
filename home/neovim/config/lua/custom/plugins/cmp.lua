-- Completion Plugin Setup
local cmp = require 'cmp'
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
    completion = cmp.config.window.bordered(),
    documentation = cmp.config.window.bordered(),
  },
  formatting = {
    fields = { 'menu', 'abbr', 'kind' },
    format = function(entry, item)
      local menu_icon = {
        nvim_lsp = 'λ',
        nvim_lua = '',
        vsnip = '⋗',
        treesitter = '',
        buffer = 'Ω',
        path = '🖫',
        git = '',
        tmux = '',
        zsh = '',
        clippy = '📎',
        spell = '暈',
      }
      item.menu = menu_icon[entry.source.name]
      return item
    end,
  },
})
