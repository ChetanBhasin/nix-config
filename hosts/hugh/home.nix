{ config, pkgs, ... }: {
  imports = [ ../../home ];
  home-config-manager = {
    includeFonts = true;
    isDarwin = true;
    enableExtras = true;
    enableProf = true;
  };
}
