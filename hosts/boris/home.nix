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
      secretspec
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
    enableProf = true;
    enableHyprland = true;
  };
}
