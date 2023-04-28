{ config, pkgs, ... }: {
  programs.direnv.enable = true;
  programs.direnv.enableZshIntegration = true;
  programs.direnv.nix-direnv.enable = true;

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.alacritty = {
    enable = true;
    package = pkgs.alacritty;
  };

  xdg.configFile."alacritty/alacritty.yml".source = ./alacritty.yaml;
}
