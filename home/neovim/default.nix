{ config, pkgs, lib, ... }:
with lib;
let python-debug = pkgs.python3.withPackages (p: with p; [ debugpy ]);
in {
  config = {
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      extraPackages = with pkgs;
        [ lua ctags ] ++ lib.optionals pkgs.stdenv.isDarwin [
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.CoreFoundation
          darwin.apple_sdk.frameworks.CoreServices
          (rust-bin.stable.latest.default.override {
            extensions = [ "rust-src" "rust-analyzer" ];
            targets = [ "aarch64-apple-darwin" "wasm32-unknown-unknown" ];
          })
        ];
      plugins = with pkgs.vimPlugins; [
        {
          plugin = nvim-web-devicons;
          config = ''
            packadd! nvim-web-devicons
            :luafile ${./includes/devicons.lua}
          '';
        }
        {
          plugin = auto-pairs;
          config = ''
            packadd! auto-pairs 
          '';
        }
        nvim-lspconfig
        {
          plugin = fidget-nvim;
          config = ''
            packadd! fidget.nvim
            :lua require"fidget".setup{}
          '';
        }
        {
          plugin = nord-nvim;
          config = ''
            packadd! nord.nvim
            colorscheme nord
          '';
        }
        {
          plugin = nvim-dap;
          config = ''
            packadd! nvim-dap
          '';
        }
        {
          plugin = rust-tools-nvim;
          config = ''
            packadd! rust-tools.nvim
            :luafile ${./includes/rust-tools.lua}
          '';
        }
        vim-vsnip-integ
        {
          plugin = vim-vsnip;
          config = ''
            packadd! vim-vsnip
            packadd! vim-vsnip-integ
          '';
        }
        cmp-nvim-lsp
        cmp-vsnip
        cmp-path
        cmp-buffer
        cmp-nvim-lsp-signature-help
        cmp-nvim-lua
        {
          plugin = nvim-cmp;
          config = ''
            packadd! nvim-cmp
            packadd! cmp-nvim-lsp
            packadd! cmp-vsnip
            packadd! cmp-path
            packadd! cmp-buffer
            packadd! cmp-nvim-lsp-signature-help
            packadd! cmp-nvim-lua
            :luafile ${./includes/cmp.lua}
          '';
        }
        {
          plugin = nvim-treesitter;
          config = ''
            packadd! nvim-treesitter
            :luafile ${./includes/treesitter.lua}
          '';
        }
        {
          plugin = vim-floaterm;
          config = ''
            packadd! vim-floaterm
            :luafile ${./includes/floaterm.lua}
          '';
        }
        plenary-nvim
        {
          plugin = telescope-nvim;
          config = ''
            packadd! plenary.nvim
            packadd! telescope.nvim
            nnoremap <leader>ff <cmd>Telescope find_files<cr>
            nnoremap <leader>fg <cmd>Telescope live_grep<cr>
            nnoremap <leader>fb <cmd>Telescope buffers<cr>
            nnoremap <leader>fh <cmd>Telescope help_tags<cr>
          '';
        }
        {
          plugin = nvim-tree-lua;
          config = ''
            packadd! nvim-tree.lua
            :lua require("nvim-tree").setup()
            nnoremap <leader>dd <cmd>NvimTreeToggle<cr>
            nnoremap <leader>df <cmd>NvimTreeFindFile<cr>
          '';
        }
        tagbar
        {
          plugin = trouble-nvim;
          config = ''
            packadd! trouble.nvim
            :lua require("trouble").setup {}
          '';
        }
        {
          plugin = comment-nvim;
          config = ''
            packadd! comment.nvim
            :lua require("Comment").setup()
          '';
        }
        {
          plugin = impatient-nvim;
          config = ''
            packadd! impatient.nvim
            :lua require('impatient')
          '';
        }
      ];
      extraConfig = ''
        set nu
        set ai
        set si
        set shiftwidth=2
        set number relativenumber
        nmap <leader>ss :TagbarToggle<CR>
        :luafile ${./includes/default.lua}
        map <leader>;
      '';
    };
  };
}
