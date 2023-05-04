return {
  {
    "rust-lang/rust.vim",
    ft = { "rust" },
    init = function()
      vim.g.rustfmt_autosave = 1
    end,
  },
  {
    "simrat39/rust-tools.nvim",
    ft = { "rust" },
    dependencies = "neovim/nvim-lspconfig",
    opts = function()
      local on_attach = require("plugins.configs.lspconfig").on_attach
      local capabilities = require("plugins.configs.lspconfig").capabilities
      return {
        server = {
          on_attach = on_attach,
          capabilities = capabilities,
        },
      }
    end,
    config = function(_, opts)
      require("rust-tools").setup(opts)
    end,
  },
  {
    "saecki/crates.nvim",
    ft = { "rust", "toml" },
    dependencies = "hrsh7th/nvim-cmp",
    config = function(_, opts)
      local crates = require("crates")
      crates.setup(opts)
      crates.show()
    end,
  },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      {
        "zbirenbaum/copilot-cmp",
        config = function()
          require("copilot_cmp").setup()
        end,
      },
    },
    opts = {
      sources = {
        { name = "nvim_lsp" },
        { name = "luasnip" },
        { name = "buffer" },
        { name = "nvim_lua" },
        { name = "path" },
        { name = "copilot" },
        { name = "crates" },
      },
    },
  },
  {
    "zbirenbaum/copilot.lua",
    event = "InsertEnter",
    cmd = "Copilot",
    config = function()
      require("copilot").setup({})
    end,
    enabled = true,
  },
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "rust-analyzer",
        "lua-language-server",
        "html-lsp",
        "prettier",
        "stylua",
        "jsonnet-language-server",
        "yaml-language-server",
        "rnix-lsp",
        "terraform-ls",
        "tailwindcss-language-server",
        "typescript-language-server"
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local on_attach = require("plugins.configs.lspconfig").on_attach
      local capabilities = require("plugins.configs.lspconfig").capabilities
      local lspconfig = require "lspconfig"
      local servers = { "lua_ls", "html", "jsonnet_ls", "yamlls" }
      for _, lsp in ipairs(servers) do
        lspconfig[lsp].setup {
          on_attach = on_attach,
          capabilities = capabilities,
        }
      end
      lspconfig.tsserver.setup({
        on_attach = on_attach,
        capabilities = capabilities,
        filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "typescript.tsx" },
        root_dir = lspconfig.util.root_pattern("package.json", "tsconfig.json", "jsconfig.json"),
        init_options = {
          hostInfo = "neovim",
        },
        single_file_support = true,
      })
      -- lspconfig.rust_analyzer.setup({
      --   on_attach = on_attach,
      --   capabilities = capabilities,
      --   filetypes = { "rust" },
      --   root_dir = lspconfig.util.root_pattern("Cargo.toml"),
      --   settings = {
      --     ['rust-analyzer'] = {
      --       cargo = {
      --         allFeatures = true,
      --       },
      --     },
      --   },
      -- })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        -- defaults 
        "vim",
        "lua",

        -- web dev 
        "html",
        "css",
        "javascript",
        "typescript",
        "tsx",
        "json",
        "yaml",
        "jsonnet",
        -- "vue", "svelte",

       -- low level
        "c",
        "rust",
        "zig"
      },
    },
  },
}
