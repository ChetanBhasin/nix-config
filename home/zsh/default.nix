{ config, pkgs, ... }: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    defaultKeymap = "viins";
    history.extended = true;
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

    initExtra = ''
      ${builtins.readFile ./sources.sh}
    '';

    plugins = [
      {
        name = "zsh-autosuggestions";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-autosuggestions";
          rev = "v0.6.3";
          sha256 = "sha256-rCTKzRg2DktT5X/f99pYTwZmSGD3XEFf9Vdenn4VEME=";
        };
      }
      {
        name = "zsh-syntax-highlighting";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-syntax-highlighting";
          rev = "be3882aeb054d01f6667facc31522e82f00b5e94";
          sha256 = "0w8x5ilpwx90s2s2y56vbzq92ircmrf0l5x8hz4g1nx3qzawv6af";
        };
      }
      {
        name = "fzf-zsh-plugin";
        src = pkgs.fetchFromGitHub {
          owner = "unixorn";
          repo = "fzf-zsh-plugin";
          rev = "master";
          sha256 = "sha256-rCTKzRg2DktT5X/f99pYTwZmSGD3XEFf9Vdenn4VEME=";
        };
      }
      {
        name = "fzf-tab";
        src = pkgs.fetchFromGitHub {
          owner = "Aloxaf";
          repo = "fzf-tab";
          rev = "master";
          sha256 = "dPe5CLCAuuuLGRdRCt/nNruxMrP9f/oddRxERkgm1FE=";
        };
      }
    ];
  };
}
