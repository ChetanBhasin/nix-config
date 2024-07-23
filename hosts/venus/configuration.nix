{ config, pkgs, ... }:

{
  imports = [ ./server.nix ];

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  security.sudo.wheelNeedsPassword = false;

  users.users.chetan = {
    isNormalUser = true;
    description = "Chetan";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ neovim k3d ];
  };

  networking.networkmanager.enable = true;
  services.openssh.enable = true;

  services.tailscale = {
    enable = true;
    authKeyFile = "/run/keys/tailscale.auth";
  };

  environment.systemPackages = [ pkgs.nextcloud28 ];

  system.stateVersion = "23.05";
}
