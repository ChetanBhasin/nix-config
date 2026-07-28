{ pkgs, ... }:
{
  imports = [ ../../home ];

  home = {
    packages = with pkgs; [
      (_1password-gui.override {
        polkitPolicyOwners = [ "chetan" ];
      })
      cryptomator
      discord
      firefox
      google-chrome
      lens
      obsidian
      proton-pass
      protonmail-bridge
      protonmail-desktop
      proton-vpn
      signal-desktop
      slack
      spotify
      telegram-desktop
      vlc
      yubioath-flutter
      zoom-us
    ];
    sessionVariables = {
      BROWSER = "firefox";
      TERMINAL = "alacritty";
    };
  };

  home-config-manager = {
    includeFonts = true;
    isDarwin = false;
    enableExtras = true;
    enableProf = true;
  };
}
