# Standalone Zellij module for Home Manager.
# Can be imported via: inputs.nix-config.homeManagerModules.zellij
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.cb.zellij;
  zellijConfigPath = ../../home/zellij;
  zellijVersion = "0.45.0";
  zellijSource = pkgs.fetchFromGitHub {
    owner = "zellij-org";
    repo = "zellij";
    tag = "v${zellijVersion}";
    hash = "sha256-1kS0DuF+mO60jf2UZTKhwZuekO31aoXIEytGuljzd08=";
  };
  zellijCargoHash = "sha256-ZwxoqdZ73/HvdkdNWOKW3Av6htI/vCFcJ0zVpSL1SuU=";
  zellijBaseUnwrapped =
    if lib.versionOlder pkgs.zellij.version zellijVersion then
      pkgs.zellij-unwrapped.overrideAttrs (oldAttrs: {
        version = zellijVersion;
        src = zellijSource;
        cargoHash = zellijCargoHash;
        # buildRustPackage has already materialized cargoDeps by the time
        # overrideAttrs runs, so rebuild it from the overridden source and hash.
        cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
          name = "zellij-unwrapped-${zellijVersion}";
          src = zellijSource;
          hash = zellijCargoHash;
        };

        nativeBuildInputs = builtins.filter (input: input != pkgs.mandown) oldAttrs.nativeBuildInputs;

        # v0.45.0 removed docs/MANPAGE.md, so replace rather than extend the
        # pinned v0.44.3 install phase that invokes mandown on that file.
        postInstall = lib.optionalString (pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform) ''
          installShellCompletion --cmd zellij \
            --bash <($out/bin/zellij setup --generate-completion bash) \
            --fish <($out/bin/zellij setup --generate-completion fish) \
            --zsh <($out/bin/zellij setup --generate-completion zsh)
        '';
      })
    else
      pkgs.zellij-unwrapped;
  zellijUnwrapped = zellijBaseUnwrapped.overrideAttrs (oldAttrs: {
    # Zellij 0.45 has no switch for its pane-frame scroll counters, while
    # zjstatus already makes Scroll mode visible in the top status bar.
    patches = (oldAttrs.patches or [ ]) ++ [
      (zellijConfigPath + "/zellij-hide-pane-scroll-indicators.patch")
      (zellijConfigPath + "/zellij-prefer-vertical-pane-fill.patch")
      (zellijConfigPath + "/zellij-session-manager-vim-navigation.patch")
    ];
  });
  zellij = pkgs.zellij.override { zellij-unwrapped = zellijUnwrapped; };
  patchedZjstatus = pkgs.zellijPlugins.wrapper "zjstatus" (
    pkgs.zellijPlugins.zjstatus.unwrapped.overrideAttrs (oldAttrs: {
      patches = (oldAttrs.patches or [ ]) ++ [
        (zellijConfigPath + "/zjstatus-focused-pane-title.patch")
      ];
    })
  );
  zellijBatteryStatus = pkgs.writeShellApplication {
    name = "zellij-battery-status";
    text =
      (
        if pkgs.stdenv.hostPlatform.isDarwin then
          ''
            if ! battery_info="$(/usr/bin/pmset -g batt 2>/dev/null)"; then
              exit 0
            fi
            [[ "$battery_info" =~ ([0-9]{1,3})% ]] || exit 0
            percentage="''${BASH_REMATCH[1]}"

            case "$battery_info" in
              *"; charging;"*|*"; finishing charge;"*) status="charging" ;;
              *"; charged;"*) status="full" ;;
              *"; AC attached;"*|*"; attached;"*) status="attached" ;;
              *"; discharging;"*) status="discharging" ;;
              *) status="unknown" ;;
            esac
          ''
        else if pkgs.stdenv.hostPlatform.isLinux then
          ''
            battery=""
            for candidate in /sys/class/power_supply/*; do
              [[ -r "$candidate/type" && -r "$candidate/capacity" ]] || continue
              IFS= read -r battery_type < "$candidate/type" || continue
              [[ "$battery_type" == "Battery" ]] || continue
              battery="$candidate"
              break
            done
            [[ -n "$battery" ]] || exit 0

            IFS= read -r percentage < "$battery/capacity" || exit 0
            raw_status="unknown"
            if [[ -r "$battery/status" ]]; then
              IFS= read -r raw_status < "$battery/status" || raw_status="unknown"
            fi

            case "''${raw_status,,}" in
              charging) status="charging" ;;
              full) status="full" ;;
              "not charging") status="attached" ;;
              discharging) status="discharging" ;;
              *) status="unknown" ;;
            esac
          ''
        else
          ''
            exit 0
          ''
      )
      + ''
        [[ "$percentage" =~ ^[0-9]+$ ]] || exit 0
        percentage=$((10#$percentage))
        (( percentage >= 0 && percentage <= 100 )) || exit 0

        case "$status" in
          charging|attached) icon="󰂄" ;;
          full) icon="󰁹" ;;
          unknown) icon="󰂑" ;;
          *)
            if (( percentage >= 95 )); then icon="󰁹"
            elif (( percentage >= 80 )); then icon="󰂁"
            elif (( percentage >= 65 )); then icon="󰁿"
            elif (( percentage >= 50 )); then icon="󰁾"
            elif (( percentage >= 35 )); then icon="󰁽"
            elif (( percentage >= 20 )); then icon="󰁼"
            elif (( percentage > 5 )); then icon="󰁻"
            else icon="󰂎"
            fi
            ;;
        esac

        printf '%s %d%%\n' "$icon" "$percentage"
      '';
  };
  zellijLayout = pkgs.replaceVars (zellijConfigPath + "/lanes.kdl") {
    zellijBatteryCommand = "${zellijBatteryStatus}/bin/zellij-battery-status";
  };
  vimZellijNavigator = pkgs.fetchurl {
    url = "https://github.com/hiasr/vim-zellij-navigator/releases/download/0.3.0/vim-zellij-navigator.wasm";
    hash = "sha256-d+Wi9i98GmmMryV0ST1ddVh+D9h3z7o0xIyvcxwkxY0=";
  };
  zextract = pkgs.fetchurl {
    url = "https://github.com/codingfragments/zellij-zextract/releases/download/v0.4.0/zextract.wasm";
    hash = "sha256-LnneanEAK2IcBo6kIyuzyuPt9nb/mSjL0+AC22eh/BA=";
  };
  zellijKeymapHelp = pkgs.writeShellApplication {
    name = "zellij-keymap-help";
    runtimeInputs = [ pkgs.fzf ];
    text = ''
      entries=(
        $'GLOBAL\tCtrl-Space\tOpen command mode'
        $'GLOBAL\tCtrl-g\tEnter or leave pass-through mode'
        $'GLOBAL\tCtrl-h/j/k/l\tFocus pane'
        $'GLOBAL\tAlt-h/l\tPrevious or next tab'
        $'GLOBAL\tCmd-1..9\tSelect tab on macOS'
        $'GLOBAL\tCtrl-Shift-1..9\tSelect tab on Linux'

        $'COMMAND\tp / w / s\tOpen pane, tab, or session mode'
        $'COMMAND\t[ / g\tOpen scroll or Git mode'
        $'COMMAND\tc\tCreate tab with lanes layout'
        $'COMMAND\tn / N\tNext or previous tab'
        $'COMMAND\t1..9 / ,\tSelect or rename tab'
        $'COMMAND\th/j/k/l\tFocus pane'
        $'COMMAND\t; / o\tPrevious or next pane'
        $'COMMAND\t| / -\tSplit focused pane right / below'
        $'COMMAND\tz / x\tFullscreen or close pane'
        $'COMMAND\tSpace\tNormalize panes to lanes layout'
        $'COMMAND\tm / t\tToggle mouse or pane frames'
        $'COMMAND\tCtrl-l / d\tClear screen or detach'
        $'COMMAND\tP / S\tProjects or session manager'
        $'COMMAND\tT / ?\tExtract text or show this help'

        $'PANE\th/j/k/l\tFocus pane'
        $'PANE\t| / -\tSplit focused pane right / below'
        $'PANE\tx / z\tClose or fullscreen pane'
        $'PANE\tm / r\tGroup pane or enter resize mode'
        $'PANE\tL\tNormalize panes to lanes layout'
        $'PANE\tw / e\tShow floats or float/embed pane'
        $'PANE\tR / i\tRename or pin pane'

        $'RESIZE\th/j/k/l\tGrow the selected edge'
        $'RESIZE\tH/J/K/L\tShrink the selected edge'
        $'RESIZE\t+ / -\tGrow or shrink the pane'

        $'TAB\th / j\tPrevious or next tab'
        $'TAB\tn / k / r\tCreate, close, or rename tab'
        $'TAB\tl / s\tOpen hierarchy or sync input'
        $'TAB\t< / >\tMove tab left or right'
        $'TAB\t1..9 / Tab\tSelect tab or return to last tab'

        $'SESSION\ts / c / p\tManager, configuration, or plugins'
        $'SESSION\td\tDetach'

        $'GIT\tg / s / l / d\tLazygit, status, log, or diff'

        $'SCROLL\tj/k / Ctrl-f/b\tLine or page down/up'
        $'SCROLL\td/u / g/G\tHalf-page or top/bottom'
        $'SCROLL\t/\tSearch scrollback'
        $'SCROLL\tv\tOpen in Neovim to select and copy'
        $'COPY\tv/V/C-v, move, y\tSelect chars/lines/block, then copy'
        $'PASTE\tCmd-V / Ctrl-Shift-V\tPaste system clipboard in Normal mode'
        $'SEARCH\tn/N\tNext or previous match'
        $'SEARCH\tc / w / o\tToggle case, wrap, or whole-word'
      )

      for entry in "''${entries[@]}"; do
        IFS=$'\t' read -r mode keys action <<< "$entry"
        printf '%-9s %-19s %s\n' "$mode" "$keys" "$action"
      done \
        | fzf \
          --border=rounded \
          --border-label=' Zellij keys ' \
          --cycle \
          --header='MODE      KEYS                ACTION · type to filter · Esc closes' \
          --header-first \
          --layout=reverse \
          --no-multi \
          --prompt='Keys: ' \
          >/dev/null \
        || true
    '';
  };
  zellijSendToPane = pkgs.writeShellApplication {
    name = "zellij-send-to-pane";
    runtimeInputs = [ zellij ];
    text = ''
      usage() {
        printf '%s\n' \
          'Usage: zellij-send-to-pane [--session NAME] [--enter] terminal_N [TEXT...]' \
          '       zellij-send-to-pane [--session NAME] --list' \
          "" \
          'Stages TEXT in a terminal pane using bracketed paste.' \
          'Enter is sent only when --enter is present.' \
          'If TEXT is omitted, the payload is read from stdin.'
      }

      fail() {
        printf 'zellij-send-to-pane: %s\n' "$1" >&2
        printf 'Try zellij-send-to-pane --help for usage.\n' >&2
        exit 2
      }

      session_name="''${ZELLIJ_SESSION_NAME:-}"
      send_enter=false
      list_panes=false

      while (( $# > 0 )); do
        case "$1" in
          --session)
            (( $# >= 2 )) || fail '--session requires a name'
            session_name="$2"
            shift 2
            ;;
          --enter)
            send_enter=true
            shift
            ;;
          --list)
            list_panes=true
            shift
            ;;
          -h|--help)
            usage
            exit 0
            ;;
          --)
            shift
            break
            ;;
          -*)
            fail "unknown option: $1"
            ;;
          *)
            break
            ;;
        esac
      done

      [[ -n "$session_name" ]] || fail 'no session selected; use --session or run inside Zellij'

      if [[ "$list_panes" == true ]]; then
        [[ "$send_enter" == false ]] || fail '--enter cannot be combined with --list'
        (( $# == 0 )) || fail '--list does not accept a pane or text'
        exec zellij --session "$session_name" action list-panes --all
      fi

      (( $# >= 1 )) || fail 'a type-qualified pane ID such as terminal_3 is required'
      pane="$1"
      shift
      [[ "$pane" =~ ^terminal_[0-9]+$ ]] || fail "invalid pane ID: $pane (expected terminal_N)"

      if (( $# > 0 )); then
        payload="$*"
      elif [[ ! -t 0 ]]; then
        payload=""
        IFS= read -r -d "" payload || true
      else
        fail 'TEXT is required when stdin is a terminal'
      fi

      zellij --session "$session_name" action paste --pane-id "$pane" -- "$payload"
      if [[ "$send_enter" == true ]]; then
        zellij --session "$session_name" action send-keys --pane-id "$pane" Enter
      fi
    '';
  };
  zellijProjectPicker = pkgs.writeShellApplication {
    name = "zellij-project-picker";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.fzf
      zellij
    ];
    text = ''
      fail() {
        printf 'zellij-project-picker: %s\n' "$1" >&2
        if [[ -t 0 ]]; then
          printf 'Press Enter to close.\n' >&2
          IFS= read -r _ || true
        fi
        exit 1
      }

      [[ -n "''${ZELLIJ_SESSION_NAME:-}" ]] || fail 'run this command inside Zellij'

      projects_root="$HOME/Projects"
      [[ -d "$projects_root" ]] || fail "$projects_root does not exist"

      project_paths=()
      shopt -s nullglob
      for project_path in "$projects_root"/*; do
        [[ -d "$project_path" ]] || continue
        project_name="''${project_path##*/}"
        [[ "$project_name" =~ [[:cntrl:]] ]] && continue
        [[ -n "''${project_name//[[:space:]]/}" ]] || continue
        project_paths+=("$project_path")
      done
      shopt -u nullglob
      (( ''${#project_paths[@]} > 0 )) || fail "no projects found in $projects_root"

      if ! IFS= read -r -d "" project_dir < <(
        printf '%s\0' "''${project_paths[@]}" \
          | sort --zero-terminated \
          | fzf \
            --read0 \
            --print0 \
            --delimiter=/ \
            --with-nth=-1 \
            --prompt='Project: ' \
            --layout=reverse \
            --border
      ); then
        exit 0
      fi
      [[ -n "$project_dir" ]] || exit 0

      session_name="''${project_dir##*/}"

      session_is_live() {
        local panes
        panes="$(
          zellij --session="$session_name" action list-panes --json 2>/dev/null || true
        )"
        [[ "$panes" == \[* ]]
      }

      if [[ "$session_name" == "$ZELLIJ_SESSION_NAME" ]]; then
        exit 0
      fi

      if ! session_is_live; then
        # Zellij 0.44.3 ignores --cwd while switch-session creates a session.
        # Starting its server from the project directory preserves the cwd,
        # and the explicit layout avoids the Session Manager's layout chooser.
        if ! create_error="$(
          cd -- "$project_dir"
          unset ZELLIJ ZELLIJ_SESSION_NAME ZELLIJ_PANE_ID
          zellij --layout lanes attach --create-background -- "$session_name" 2>&1
        )" && ! session_is_live; then
          fail "$create_error"
        fi
      fi

      exec zellij --session="$ZELLIJ_SESSION_NAME" action switch-session -- "$session_name"
    '';
  };
in
{
  options.cb.zellij.enable = lib.mkEnableOption "Chetan's opt-in Zellij configuration";

  config = lib.mkIf cfg.enable {
    programs.zellij = {
      enable = true;
      package = zellij;

      # Starting Zellij remains an explicit choice while tmux is the default.
      enableBashIntegration = false;
      enableFishIntegration = false;
      enableZshIntegration = false;
      attachExistingSession = false;
      exitShellOnExit = false;

      layouts.lanes = zellijLayout;

      settings = {
        default_layout = "lanes";
        default_mode = "normal";
        default_shell = "${pkgs.zsh}/bin/zsh";

        theme = "gruvbox-night";
        pane_frames = true;
        # Zellij 0.45 defaults to title-only separators; retain full pane boxes.
        pane_frame_style = "full";
        mouse_mode = true;
        # Directional splits define lane ownership. Keep closure local to that
        # topology; Ctrl-Space Space / pane-mode L remains an explicit reflow.
        auto_layout = false;
        stacked_resize = false;
        visual_bell = true;

        scroll_buffer_size = 50000;
        copy_clipboard = "system";
        copy_on_select = true;

        on_force_close = "detach";
        session_serialization = true;
        serialize_pane_viewport = true;
        scrollback_lines_to_serialize = 10000;
        serialization_interval = 60;
        disable_session_metadata = false;

        show_release_notes = false;
        show_startup_tips = false;
        support_kitty_keyboard_protocol = true;
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        # Linux intentionally uses Zellij's OSC 52 clipboard support.
        copy_command = "pbcopy";
      };

      # Raw KDL keeps the plugin alias, UI options, and key map readable while
      # avoiding Home Manager's automatic headless plugin loading.
      extraConfig = ''
        ${builtins.readFile (zellijConfigPath + "/gruvbox-night.kdl")}

        plugins {
            zjstatus location="file:${config.home.homeDirectory}/.config/zellij/plugins/zjstatus.wasm"
            vim-zellij-navigator location="file:${config.home.homeDirectory}/.config/zellij/plugins/vim-zellij-navigator.wasm"
            zextract location="file:${config.home.homeDirectory}/.config/zellij/plugins/zextract.wasm"
        }

        load_plugins {
            vim-zellij-navigator
        }

        ui {
            pane_frames {
                hide_session_name true
                rounded_corners true
            }
        }

        ${builtins.readFile (zellijConfigPath + "/keybinds.kdl")}
      '';
    };

    xdg.configFile."zellij/plugins/zjstatus.wasm".source = patchedZjstatus;
    xdg.configFile."zellij/plugins/vim-zellij-navigator.wasm".source = vimZellijNavigator;
    xdg.configFile."zellij/plugins/zextract.wasm".source = zextract;
    xdg.configFile."zellij/zextract.kdl".text = ''
      log_level "warn"

      ui {
          preview "off"
      }

      // v0.4.0 parses mask_secrets but does not apply it while rendering.
      // Do not extract secret-shaped values in the first place.
      patterns {
          disable "secret"
      }

      grab {
          default_profile "quick"
          profiles {
              quick {
                  source "scrollback"
                  lines 150
              }
              full {
                  source "scrollback"
                  progress true
                  disable "secret"
              }
          }
      }

      ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        // zextract v0.4.0 otherwise hard-codes the macOS `open` command.
        actions {
            url {
                open command "${pkgs.xdg-utils}/bin/xdg-open '{url}'"
            }
        }
      ''}
    '';

    # Prefix-g opens lazygit; the helpers use Zellij's native CLI actions.
    home.packages = [
      pkgs.lazygit
      zellijKeymapHelp
      zellijProjectPicker
      zellijSendToPane
    ];
  };
}
