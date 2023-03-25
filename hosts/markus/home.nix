{ config, pkgs, ... }: {
  imports = [ ../../home ];
  home-config-manager = {
    includeFonts = true;
    isDarwin = true;
    enableExtras = false;
    enableProf = true;
  };
}
