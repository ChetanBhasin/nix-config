{ config, pkgs, lib, ... }: {
  system.stateVersion = "23.05";
  boot = {
    kernelPackages = pkgs.linuxPackages;
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  imports = [ ./hardware-configuration.nix ];

  nixpkgs.system = "x86_64-linux";

  networking = {
    hostName = "dtest";
    networkmanager = { enable = true; };
  };

  time.timeZone = "America/New_York";

}
