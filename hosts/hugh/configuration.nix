{ config, pkgs, ... }: {

  darwin-config-manager = {
    enableSudoTouch = true;
    enableExtras = true;
    enableProf = false;
    theme = "nord";

    extraCasks = [
      "1password"
      "balenaetcher"
      "proton-mail-bridge"
      "zoom"
      "steam"
      "whatsapp@beta"
      "shureplus-motiv"
      "screen-studio"
      "netdownloadhelpercoapp"
      "insta360-studio"
      "cryptomator"
    ];
  };

  environment.systemPackages = with pkgs; [ cloudflared ];

  imports = [ ../../darwin ];
}
