{ config, pkgs, lib, ... }:
with lib; {
  config = {
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      withNodeJs = true;
      withPython3 = true;
      extraPackages = with pkgs;
        [ lua go ctags stylua ripgrep gzip nerdfonts ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.CoreFoundation
          darwin.apple_sdk.frameworks.CoreServices
        ];
    };

    xdg.configFile."nvim".source = ./nvchad;
    xdg.configFile."nvim".recursive = true;
  };
}
