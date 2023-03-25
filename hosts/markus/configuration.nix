{ config, pkgs, ... }: {

  darwin-config-manager = {
    enableSudoTouch = false;
    enableExtras = false;
    enableProf = true;
    theme = "nord";
  };

  imports = [ ../../darwin ];
}
