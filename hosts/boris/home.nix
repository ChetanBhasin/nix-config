{ pkgs, ... }:
{
  imports = [ ../../home ];

  home = {
    packages = with pkgs; [
      (_1password-gui.override {
        polkitPolicyOwners = [ "chetan" ];
      })
      cryptomator
      protonmail-bridge
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
    enableHyprland = true;
  };
}
