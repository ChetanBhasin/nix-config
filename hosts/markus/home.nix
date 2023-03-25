{ config, pkgs, ... }: {
  imports = [ ../../home ];
  home-config-manager = {
    includeFonts = true;
    enableExtras = false;
    enableProf = true;
  };
}
