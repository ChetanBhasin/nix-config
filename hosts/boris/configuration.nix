{ pkgs, ... }:
let
  sshAuthorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXQGdevTUYR59AYrbwcsPdu6qIsuPSRCcFEpG8YiXY8 chetan@chetan-mac.local"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC8y+WOiiqxKGRQHGdtRGL2R4Ptqs7uEXX89WwvUQTc9A2zTFjGNcQvDCP6+qw6FQgDCaLdNozojfPQxo/VqMiWf1KXvBOPMONc+AUURhPxw8lD1FSc5AsLAw68BrxnFLbYrKmJT6qr3Ap/D6NGNlJUN3mR/e8Bj2wpKNSidmn9aDBxuGLkBmYJ8K8Wdalg47WwQ7wvzxCn4MFjM8CINyaI3p0mouZdCeCd/JcJgeLqN1JGuHCdgwzS9FgAWwQ0s/zb33icxS3qlHYLOch8YpD1wCceHJEv8dRQxwoEbdho9VwUzZGE8y2YPLxNLShSjUEPK5rLbfz4kUrWZCEX0LHhwyBKW0u8O7RArCKVDjJkiVEWoIrTmYx3CxppYnuyKPe85vUwqQzafN1EVvtfwQcJHBknG/9Fo5sU+juuTMIbFHNwFjBH4MzOnIRBAV2lGy4YsGZwE/+HVB9kFqZf3KrBeRSZsNMUxC0AXapOHKimHyUyHS/bJUH3onqPV1cD8/k= chetan@Chetans-Air"
  ];
in
{
  imports = [
    ../../bootconfig/boris.nix
    ../../modules/nixos/remote-unlock-initrd-ssh.nix
    ../../systemPackages
  ];

  networking = {
    hostName = "boris";
    networkmanager.enable = true;
  };

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  nix = {
    settings = {
      auto-optimise-store = true;
      builders-use-substitutes = true;
      experimental-features = [
        "external-builders"
        "nix-command"
        "flakes"
      ];
      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
        "https://devenv.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  users.users = {
    chetan = {
      description = "Chetan";
      extraGroups = [
        "audio"
        "networkmanager"
        "video"
      ];
      openssh.authorizedKeys.keys = sshAuthorizedKeys;
    };
    root.openssh.authorizedKeys.keys = sshAuthorizedKeys;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.xserver = {
    enable = true;
    xkb.layout = "us";
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
  };

  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    enableRedistributableFirmware = true;
  };

  services = {
    fwupd.enable = true;
    pcscd.enable = true;
    power-profiles-daemon.enable = true;
    printing.enable = true;
    tailscale.enable = true;
  };

  programs = {
    _1password.enable = true;
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "chetan" ];
    };
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    nix-index.enable = true;
    steam.enable = true;
    zsh.enable = true;
  };

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  environment = {
    variables = {
      BROWSER = "firefox";
      EDITOR = "nvim";
      TERMINAL = "alacritty";
      VISUAL = "nvim";
    };
    systemPackages = with pkgs; [
      cloudflared
      cryptomator
      discord
      firefox
      google-chrome
      jdk
      lens
      obsidian
      proton-pass
      protonmail-bridge
      protonmail-desktop
      proton-vpn
      podman-compose
      podman-tui
      signal-desktop
      slack
      spotify
      telegram-desktop
      vlc
      yubioath-flutter
      zoom-us
    ];
  };

  system.stateVersion = "26.05";
}
