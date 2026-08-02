{ config, pkgs, ... }:
let
  sshAuthorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXQGdevTUYR59AYrbwcsPdu6qIsuPSRCcFEpG8YiXY8 chetan@chetan-mac.local"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC8y+WOiiqxKGRQHGdtRGL2R4Ptqs7uEXX89WwvUQTc9A2zTFjGNcQvDCP6+qw6FQgDCaLdNozojfPQxo/VqMiWf1KXvBOPMONc+AUURhPxw8lD1FSc5AsLAw68BrxnFLbYrKmJT6qr3Ap/D6NGNlJUN3mR/e8Bj2wpKNSidmn9aDBxuGLkBmYJ8K8Wdalg47WwQ7wvzxCn4MFjM8CINyaI3p0mouZdCeCd/JcJgeLqN1JGuHCdgwzS9FgAWwQ0s/zb33icxS3qlHYLOch8YpD1wCceHJEv8dRQxwoEbdho9VwUzZGE8y2YPLxNLShSjUEPK5rLbfz4kUrWZCEX0LHhwyBKW0u8O7RArCKVDjJkiVEWoIrTmYx3CxppYnuyKPe85vUwqQzafN1EVvtfwQcJHBknG/9Fo5sU+juuTMIbFHNwFjBH4MzOnIRBAV2lGy4YsGZwE/+HVB9kFqZf3KrBeRSZsNMUxC0AXapOHKimHyUyHS/bJUH3onqPV1cD8/k= chetan@Chetans-Air"
  ];
  onePasswordGui = pkgs._1password-gui.override {
    polkitPolicyOwners = [ "chetan" ];
  };
  onePasswordPolkitPolicy = pkgs.runCommand "1password-polkit-policy" { } ''
    mkdir -p "$out/share/polkit-1/actions"
    ln -s \
      "${onePasswordGui}/share/polkit-1/actions/com.1password.1Password.policy" \
      "$out/share/polkit-1/actions/com.1password.1Password.policy"
  '';
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
    media = {
      isNormalUser = true;
      description = "Media";
      home = "/home/media";
      createHome = true;
      group = "media";
      extraGroups = [
        "audio"
        "input"
        "networkmanager"
        "video"
      ];
      openssh.authorizedKeys.keys = sshAuthorizedKeys;
    };
    root.openssh.authorizedKeys.keys = sshAuthorizedKeys;
  };
  users.groups.media = { };
  users.groups.onepassword.gid = config.ids.gids.onepassword;

  home-manager.users.media = import ./media.nix;

  # SDDM starts the Bigscreen session in the user's home. Keep this explicit
  # so the directory is also recreated if it is ever absent at boot.
  systemd = {
    sleep.settings.Sleep = {
      AllowHibernation = "no";
      AllowHybridSleep = "no";
      AllowSuspend = "no";
      AllowSuspendThenHibernate = "no";
    };
    tmpfiles.rules = [ "d /home/media 0750 media media -" ];
  };
  services.logind.settings.Login = {
    HandleHibernateKey = "ignore";
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleSuspendKey = "ignore";
    IdleAction = "ignore";
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

  services.displayManager = {
    autoLogin = {
      enable = true;
      user = "media";
    };
    defaultSession = "plasma-bigscreen-wayland";
    sessionPackages = [ pkgs.kdePackages.plasma-bigscreen ];
    sddm.enable = true;
  };
  services.desktopManager.plasma6.enable = true;
  services.udev.packages = [ pkgs.kdePackages.plasma-bigscreen ];
  services.xserver = {
    enable = true;
    xkb.layout = "us";
  };

  security = {
    rtkit.enable = true;
    wrappers."1Password-BrowserSupport" = {
      source = "${onePasswordGui}/share/1password/1Password-BrowserSupport";
      owner = "root";
      group = "onepassword";
      setuid = false;
      setgid = true;
    };
  };
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
    tailscale = {
      enable = true;
      extraSetFlags = [ "--accept-routes=false" ];
    };
  };

  programs = {
    _1password.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    nix-index.enable = true;
    kdeconnect.enable = true;
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
    systemPackages = with pkgs; [
      onePasswordPolkitPolicy
      cloudflared
      jdk
      kdePackages.plasma-bigscreen
      podman-compose
      podman-tui
    ];
  };

  system.stateVersion = "26.05";
}
