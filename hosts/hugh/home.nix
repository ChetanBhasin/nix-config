{ config, pkgs, ... }: {
  imports = [ ../../home ];
  home-config-manager = {
    includeFonts = true;
    enableExtras = true;
    enableProf = false;
  };
}
