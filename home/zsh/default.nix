{ config, pkgs, ... }: {
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
      ls = "exa";
      c = "z";
    };
    sessionVariables = rec {
      EDITOR = "nvim";
      OPENSSL_NO_VENDOR = "1";
      OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
      OPENSSL_DIR = "${pkgs.openssl.dev}";
      PKG_CONFIG_LIBDIR = "${pkgs.rdkafka}/lib/pkgconfig";
      LIBRARY_PATH = "LIBRARY_PATH:${pkgs.libiconv}/lib";
      PKG_CONFIG_PATH =
        "$PKG_CONFIG_PATH:${pkgs.rdkafka}/lib/pkgconfig:${pkgs.libiconv}/lib/pkgconfig";
    };

    initContent = ''
        export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
       export MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion | cut -d. -f1-2)"
      ${builtins.readFile ./sources.sh}

      # Enhanced Git functions with FZF
      fzf_git_log() {
        git log --oneline --color=always | fzf --ansi --preview 'git show --color=always {1}'
      }

      fzf_git_branch() {
        git branch -a --color=always | grep -v '/HEAD\s' | sort | fzf --ansi --preview 'git log --oneline --graph --date=short --color=always --pretty="format:%C(auto)%cd %h%d %s" $(sed s/^..// <<< {} | cut -d" " -f1) | head -'$LINES
      }

      # Override git log and git branch with FZF versions when called without arguments
      git() {
        case $1 in
          log)
            if [[ $# -eq 1 ]]; then
              fzf_git_log
            else
              command git "$@"
            fi
            ;;
          branch)
            if [[ $# -eq 1 ]]; then
              fzf_git_branch
            else
              command git "$@"
            fi
            ;;
          *)
            command git "$@"
            ;;
        esac
      }

      # Other utility functions
      fzf_kill() {
        local pid
        pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
        if [ "x$pid" != "x" ]; then
          echo $pid | xargs kill -''${1:-9}
        fi
      }

      hist_search() {
        print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +s --tac | sed 's/ *[0-9]* *//')
      }

      hist_stats() {
        history | awk '{CMD[$2]++;count++;}END { for (a in CMD)print CMD[a] " " CMD[a]/count*100 "% " a;}' | grep -v "./" | column -c3 -s " " -t | sort -nr | nl |  head -n20
      }
    '';

    plugins = [
      {
        name = "zsh-autosuggestions";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-autosuggestions";
          rev = "v0.7.0";
          sha256 = "1g3pij5qn2j7v7jjac2a63lxd97mcsgw6xq6k5p7835q9fjiid98";
        };
      }
      {
        name = "zsh-syntax-highlighting";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-syntax-highlighting";
          rev = "0.8.0";
          sha256 = "0zmq66dzasmr5pwribyh4kbkk23jxbpdw4rjxx0i7dx8jjp2lzl4";
        };
      }
      {
        name = "fzf-tab";
        src = pkgs.fetchFromGitHub {
          owner = "Aloxaf";
          repo = "fzf-tab";
          rev = "v1.1.2";
          sha256 = "061jjpgghn8d5q2m2cd2qdjwbz38qrcarldj16xvxbid4c137zs2";
        };
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
    ];
    historyWidgetOptions = [
      "--sort"
      "--exact"
      "--preview 'echo {}'"
      "--preview-window up:3:hidden:wrap"
      "--bind 'ctrl-/:toggle-preview'"
      "--bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'"
      "--color header:italic"
      "--header 'Press CTRL-Y to copy command into clipboard'"
    ];
    fileWidgetOptions = [
      "--preview 'head -100 {}'"
      "--bind 'ctrl-/:change-preview-window(down|hidden|)'"
    ];
    changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
  };
}
