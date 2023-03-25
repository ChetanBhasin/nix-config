{ config, pkgs, ... }: {

  darwin-config-manager = {
    enableSudoTouch = true;
    enableExtras = true;
    enableProf = false;
    theme = "nord";
  };

  imports = [ ../../darwin ];
}
