{ config, pkgs, ... }: {

  darwin-config-manager = {
    enableSudoTouch = true;
    enableExtras = true;
    enableProf = false;
    theme = "nord";

    # Hugh-specific applications
    extraBrews = [
      "cloudflared"
      "flyctl"
    ];

    extraCasks = [
      "1password"
      "ollama-app"
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

  imports = [ ../../darwin ];
}
