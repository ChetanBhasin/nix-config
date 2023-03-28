{ config, pkgs, lib, ... }:
with lib;
let cfg = config.linux-config;
in {

  options.linux-config = {
    enableNixOptimise = lib.mkEnableOption "nix auto optimise";
    enablePlasmaDesktop = lib.mkEnableOption "enable plasma desktop";
  };

  config = {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.efi.efiSysMountPoint = "/boot/efi";

    # Setup keyfile
    boot.initrd.secrets = { "/crypto_keyfile.bin" = null; };
    # Bootloader.
    # Enable networking
    networking.networkmanager.enable = true;

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";

    i18n.extraLocaleSettings = {
      LC_ADDRESS = "de_DE.UTF-8";
      LC_IDENTIFICATION = "de_DE.UTF-8";
      LC_MEASUREMENT = "de_DE.UTF-8";
      LC_MONETARY = "de_DE.UTF-8";
      LC_NAME = "de_DE.UTF-8";
      LC_NUMERIC = "de_DE.UTF-8";
      LC_PAPER = "de_DE.UTF-8";
      LC_TELEPHONE = "de_DE.UTF-8";
      LC_TIME = "de_DE.UTF-8";
    };

    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;

    # Set your time zone.
    time.timeZone = "Europe/Berlin";

    nix = {

      package = pkgs.nixStable;
      settings = {
        auto-optimise-store = cfg.enableNixOptimise;
        # Add cache for nix-community, used mainly for neovim nightly
        substituters = [ "https://nix-community.cachix.org" ];
        trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
      gc = optionalAttrs cfg.enableNixOptimise {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
      # Enable Flakes
      extraOptions = ''
        experimental-features = nix-command flakes
        ${optionalString cfg.enableNixOptimise ''
          min-free = ${toString (100 * 1024 * 1024)}
          max-free = ${toString (1024 * 1024 * 1024)}
        ''}
      '';
    };

    programs.zsh = {
      enable = true;
      enableCompletion = false;
      promptInit = "";
    };

    users.defaultUserShell = pkgs.zsh;

    system.stateVersion = "22.05";
  };

}
