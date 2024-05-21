{ config, pkgs, ... }:

{
  imports = [ ./server.nix ];

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  security.sudo.wheelNeedsPassword = false;

  users.users.chetan = {
    isNormalUser = true;
    description = "Chetan";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ firefox neovim ];
  };

  networking.networkmanager.enable = true;
  services.openssh.enable = true;

  services.tailscale = {
    enable = true;
    authKeyFile = "/run/keys/tailscale.auth";
  };

  system.stateVersion = "23.11";
}
