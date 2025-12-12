{ config, pkgs, lib, ... }: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    defaultKeymap = "viins";
    history = {
      extended = true;
      size = 50000;
      save = 50000;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
    };
    shellAliases = {
      c = "z";
    };
    sessionVariables = {
      EDITOR = "nvim";
      OPENSSL_NO_VENDOR = "1";
      OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
      OPENSSL_DIR = "${pkgs.openssl.dev}";
      PKG_CONFIG_LIBDIR = "${pkgs.rdkafka}/lib/pkgconfig";
      LIBRARY_PATH = "LIBRARY_PATH:${pkgs.libiconv}/lib:${pkgs.poppler}/lib";
      PKG_CONFIG_PATH =
        "$PKG_CONFIG_PATH:${pkgs.rdkafka}/lib/pkgconfig:${pkgs.libiconv}/lib/pkgconfig:${pkgs.leptonica}/lib/pkgconfig/:${pkgs.tesseract}/lib/pkgconfig";
    };

    initContent = ''
      # Source main configuration
      [[ -f ~/.sources ]] && source ~/.sources
    '';

    plugins = [
      {
        # Syntax highlighting - use nixpkgs version
        name = "zsh-syntax-highlighting";
        src = pkgs.zsh-syntax-highlighting;
        file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
      }
      {
        # FZF-powered tab completion - use nixpkgs version (v1.2.0)
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
      {
        # History substring search - fish-style
        name = "zsh-history-substring-search";
        src = pkgs.zsh-history-substring-search;
        file = "share/zsh-history-substring-search/zsh-history-substring-search.zsh";
      }
    ];
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--inline-info"
      "--color=dark"
      "--color=fg:-1,bg:-1,hl:#c678dd,fg+:#ffffff,bg+:#4b5263,hl+:#d858fe"
      "--color=info:#98c379,prompt:#61afef,pointer:#be5046,marker:#e5c07b,spinner:#61afef,header:#61afef"
      # Vim-style navigation (works alongside arrow keys)
      "--bind=alt-j:down,alt-k:up"
      "--bind=alt-h:backward-char,alt-l:forward-char"
      "--bind=alt-u:preview-half-page-up,alt-d:preview-half-page-down"
      "--bind=alt-f:preview-page-down,alt-b:preview-page-up"
      "--bind=alt-g:first,alt-G:last"
      # Keep Ctrl bindings for power users
      "--bind=ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down"
      "--bind=ctrl-f:preview-page-down,ctrl-b:preview-page-up"
      "--bind=ctrl-/:toggle-preview"
    ];
    fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidgetOptions = [
      "--preview 'bat --color=always --line-range :100 {}'"
      "--bind 'ctrl-/:change-preview-window(down|hidden|)'"
    ];
    changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git";
    changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
    historyWidgetOptions = [
      "--sort"
      "--exact"
      "--preview 'echo {}'"
      "--preview-window up:3:hidden:wrap"
      "--bind 'ctrl-/:toggle-preview'"
      "--color header:italic"
      "--header 'Press CTRL-Y to copy command into clipboard'"
    ];
  };

  # Symlink sources files to home directory
  home.file.".sources".source = ./sources.sh;
  home.file.".sources_platform".source =
    if pkgs.stdenv.isDarwin
    then ./sources_darwin.sh
    else ./sources_linux.sh;
}
