{ config, pkgs, lib, ... }:
with lib; {
  config = mkIf config.home-config-manager.isDarwin {
    home.file.".hammerspoon" = {
      source = ./hammerspoon;
      recursive = true;
    };
  };
}
