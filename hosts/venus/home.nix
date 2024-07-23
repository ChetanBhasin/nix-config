{ config, pkgs, ... }: {
  imports = [ ../../home ];
  home-config-manager = {
    includeFonts = true;
    isDarwin = false;
    enableExtras = true;
    enableProf = true;
  };
}
