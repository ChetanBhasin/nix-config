{ config, inputs, ... }:
let
  modules = config.flake.modules;
in
{
  flake.modules.nixos.boris =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      sshAuthorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXQGdevTUYR59AYrbwcsPdu6qIsuPSRCcFEpG8YiXY8 chetan@chetan-mac.local"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC8y+WOiiqxKGRQHGdtRGL2R4Ptqs7uEXX89WwvUQTc9A2zTFjGNcQvDCP6+qw6FQgDCaLdNozojfPQxo/VqMiWf1KXvBOPMONc+AUURhPxw8lD1FSc5AsLAw68BrxnFLbYrKmJT6qr3Ap/D6NGNlJUN3mR/e8Bj2wpKNSidmn9aDBxuGLkBmYJ8K8Wdalg47WwQ7wvzxCn4MFjM8CINyaI3p0mouZdCeCd/JcJgeLqN1JGuHCdgwzS9FgAWwQ0s/zb33icxS3qlHYLOch8YpD1wCceHJEv8dRQxwoEbdho9VwUzZGE8y2YPLxNLShSjUEPK5rLbfz4kUrWZCEX0LHhwyBKW0u8O7RArCKVDjJkiVEWoIrTmYx3CxppYnuyKPe85vUwqQzafN1EVvtfwQcJHBknG/9Fo5sU+juuTMIbFHNwFjBH4MzOnIRBAV2lGy4YsGZwE/+HVB9kFqZf3KrBeRSZsNMUxC0AXapOHKimHyUyHS/bJUH3onqPV1cD8/k= chetan@Chetans-Air"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINHQ2YW8tvlvb8ek6TgpwE/vwNt1DYurI90Cke6ytI0V chetan@markus"
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
        ./_hardware.nix
        modules.nixos.remote-unlock
        modules.nixos.system-packages
        modules.nixos.hyprland
      ];

      networking = {
        hostName = "boris";
        networkmanager.enable = true;
      };

      time.timeZone = "Europe/Berlin";
      i18n.defaultLocale = "en_US.UTF-8";
      console.keyMap = "us";

      # hidraw is a loadable module nothing auto-loads on this machine; OpenLogi
      # (Logitech BT keyboard/mouse remapping) cannot enumerate a single device
      # without it. Apply this, then reboot once so the module is up before the
      # Bluetooth devices reconnect (udev uaccess ACLs only attach on connect).
      boot.kernelModules = [
        "hidraw"
        "uinput"
      ];

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
      users.groups.onepassword.gid = config.ids.gids.onepassword;

      services.openssh = {
        enable = true;
        openFirewall = true;
        settings = {
          KbdInteractiveAuthentication = false;
          PasswordAuthentication = false;
          PermitRootLogin = "prohibit-password";
        };
      };

      # Secret Service for CLI tools such as SecretSpec, including in a plain TTY.
      # The module unlocks the login keyring through PAM; greetd includes that stack.
      services.gnome.gnome-keyring.enable = true;

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
        # blueman-mechanism, the privileged D-Bus/polkit helper the home-manager
        # blueman-applet needs for pairing and rfkill.
        blueman.enable = true;
        fwupd.enable = true;
        pcscd.enable = true;
        power-profiles-daemon.enable = true;
        printing.enable = true;
        # OpenLogi ships `lib/udev/rules.d/70-openlogi.rules` (TAG+="uaccess" for
        # Logitech 046D hidraw/uinput/event nodes). The `70-` prefix matters: it
        # must land before systemd's 73-seat-late.rules consumes the tag —
        # `services.udev.extraRules` (99-local.rules) is too late for uaccess.
        udev.packages = [ pkgs.openlogi ];
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

      # The greeter and other surfaces outside home-manager's fontconfig need the
      # desktop's face available system-wide.
      fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

      environment = {
        systemPackages = with pkgs; [
          onePasswordPolkitPolicy
          cloudflared
          jdk
          podman-compose
          podman-tui
          # A bare Wayland session ships no default cursor theme, so the pointer
          # falls back to a built-in arrow that reads as broken. Bibata-Original-Ice
          # is the closest standard match to the Mac pointer: sharp, white, black
          # outline.
          bibata-cursors
        ];

      };

      system.stateVersion = "26.05";
      home-manager.users.chetan =
        { pkgs, ... }:
        {
          imports = [ modules.homeManager.personal ];

          home = {
            packages = with pkgs; [
              (_1password-gui.override {
                polkitPolicyOwners = [ "chetan" ];
              })
              cryptomator
              protonmail-bridge
              zoom-us
              (writeShellApplication {
                name = "keyring-unlock";
                runtimeInputs = [
                  coreutils
                  jq
                  systemd
                ];
                text = ''
                  # SSH key authentication supplies no password for PAM to unlock with.
                  export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
                  if ! busctl --user --timeout=5s call org.freedesktop.DBus \
                    /org/freedesktop/DBus org.freedesktop.DBus GetId >/dev/null; then
                    echo "Cannot connect to your user D-Bus session." >&2
                    exit 1
                  fi

                  keyring_ready() {
                    local collection
                    collection=$(busctl --user --timeout=5s --json=short call \
                      org.freedesktop.secrets /org/freedesktop/secrets \
                      org.freedesktop.Secret.Service ReadAlias s default 2>/dev/null |
                      jq -er '.data[0] | select(. != "/" and . != "/org/freedesktop/secrets/collection/session")') || return 1
                    [[ $(busctl --user --timeout=5s get-property org.freedesktop.secrets \
                      "$collection" org.freedesktop.Secret.Collection Locked 2>/dev/null) == "b false" ]]
                  }

                  if keyring_ready; then
                    echo "Default keyring is already unlocked."
                    exit 0
                  fi

                  trap 'unset keyring_password' EXIT
                  IFS= read -r -s -p "Keyring password: " keyring_password </dev/tty
                  printf '\n' >/dev/tty
                  if [[ -z "$keyring_password" ]]; then
                    echo "An empty keyring password would leave secrets unencrypted." >&2
                    exit 1
                  fi
                  # --unlock alone starts a competing daemon. --start cannot be combined
                  # with --unlock, so replace the daemon when a manual unlock is needed.
                  printf '%s' "$keyring_password" |
                    /run/wrappers/bin/gnome-keyring-daemon \
                      --replace --daemonize --unlock --components=secrets >/dev/null
                  unset keyring_password

                  # The daemon's parent exits before initialization finishes, including
                  # when the password is wrong. Verify the result over the same D-Bus.
                  for _ in {1..20}; do
                    if keyring_ready; then
                      echo "Default keyring is unlocked."
                      exit 0
                    fi
                    sleep 0.1
                  done
                  echo "The default keyring is still missing or locked; check the keyring password and session." >&2
                  exit 1
                '';
              })
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
            enableHyprland = true;
          };
        };
    };
  flake.nixosConfigurations.boris = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      modules.nixos.boris
      modules.nixos.nix
      modules.nixos.user
      modules.nixos.nixpkgs
    ];
  };
}
