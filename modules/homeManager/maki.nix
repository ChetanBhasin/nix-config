# Standalone Maki module for Home Manager.
# Can be imported via: inputs.nix-config.homeManagerModules.maki
#
# Maki keeps its own writable state (sessions, auth tokens, memories, folder
# trust, model-tier overrides) under the platform state directory. Only the
# files Maki never writes are projected read-only from the store; the two it
# does write are seeded once and then left alone.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.cb.maki;
  theme = import ../theme/gruvbox-night.nix;
  configDir = ../../home/maki/config;

  makiConfigHome = config.home.homeDirectory + "/.config/maki";

  rv = pkgs.callPackage ../../packages/rv.nix { };

  # Maki resolves themes by file name, so the palette has to be duplicated in
  # its format. Deriving it here keeps the single source of truth in
  # modules/theme/gruvbox-night.nix alongside Alacritty, fzf and bat.
  gruvboxNightTheme = pkgs.writeText "gruvbox-night.toml" ''
    # Gruvbox Night for Maki.
    # Generated from modules/theme/gruvbox-night.nix. Do not edit by hand.

    "comment"                     = { fg = "comment" }
    "comment.block"               = { fg = "comment" }
    "comment.block.documentation" = { fg = "subtle" }
    "comment.line"                = { fg = "comment" }
    "comment.line.documentation"  = { fg = "subtle" }

    "constant"                    = { fg = "orange" }
    "constant.builtin"            = { fg = "orange" }
    "constant.builtin.boolean"    = { fg = "orange" }
    "constant.character"          = { fg = "green" }
    "constant.character.escape"   = { fg = "aqua" }
    "constant.macro"              = { fg = "orange" }
    "constant.numeric"            = { fg = "orange" }
    "constructor"                 = { fg = "yellow" }

    "error"                       = { fg = "red" }
    "warning"                     = { fg = "yellow" }
    "info"                        = { fg = "blue" }
    "hint"                        = { fg = "brown" }

    "diff.delta"                  = { fg = "yellow" }
    "diff.minus"                  = { fg = "red" }
    "diff.plus"                   = { fg = "green" }

    "function"                    = { fg = "blue" }
    "function.builtin"            = { fg = "blue" }
    "function.call"               = { fg = "blue" }
    "function.macro"              = { fg = "brown" }
    "function.method"             = { fg = "blue" }

    "keyword"                     = { fg = "purple" }
    "keyword.control.conditional" = { fg = "purple" }
    "keyword.control.exception"   = { fg = "purple" }
    "keyword.control.import"      = { fg = "purple" }
    "keyword.control.repeat"      = { fg = "purple" }
    "keyword.directive"           = { fg = "brown" }
    "keyword.function"            = { fg = "purple" }
    "keyword.operator"            = { fg = "purple" }
    "keyword.return"              = { fg = "purple" }
    "keyword.storage"             = { fg = "purple" }
    "keyword.storage.modifier"    = { fg = "purple" }
    "keyword.storage.type"        = { fg = "yellow", modifiers = ["italic"] }

    "label"                       = { fg = "blue" }
    "attribute"                   = { fg = "aqua", modifiers = ["italic"] }
    "namespace"                   = { fg = "foreground" }
    "annotation"                  = { fg = "foreground" }

    "markup.bold"                 = { fg = "yellow", modifiers = ["bold"] }
    "markup.heading"              = { fg = "blue", modifiers = ["bold"] }
    "markup.italic"               = { fg = "yellow", modifiers = ["italic"] }
    "markup.link.text"            = { fg = "blue" }
    "markup.link.url"             = { fg = "comment" }
    "markup.list"                 = { fg = "yellow" }
    "markup.quote"                = { fg = "comment", modifiers = ["italic"] }
    "markup.raw"                  = { fg = "aqua" }
    "markup.strikethrough"        = { modifiers = ["crossed_out"] }

    "punctuation"                 = { fg = "subtle" }
    "punctuation.bracket"         = { fg = "subtle" }
    "punctuation.delimiter"       = { fg = "subtle" }
    "punctuation.special"         = { fg = "brown" }

    "special"                     = { fg = "brown" }

    "string"                      = { fg = "green" }
    "string.regexp"               = { fg = "aqua" }
    "string.special"              = { fg = "aqua" }
    "string.symbol"               = { fg = "green" }

    "tag"                         = { fg = "red" }
    "tag.attribute"               = { fg = "aqua", modifiers = ["italic"] }
    "tag.delimiter"               = { fg = "subtle" }

    "type"                        = { fg = "yellow" }
    "type.builtin"                = { fg = "yellow" }
    "type.enum.variant"           = { fg = "foreground", modifiers = ["italic"] }

    "variable"                    = { fg = "red" }
    "variable.builtin"            = { fg = "red", modifiers = ["italic"] }
    "variable.other"              = { fg = "foreground" }
    "variable.other.member"       = { fg = "foreground" }
    "variable.parameter"          = { fg = "red", modifiers = ["italic"] }

    [palette]
    background     = "${theme.base00}"
    background_2   = "${theme.base01}"
    surface        = "${theme.base02}"
    foreground     = "${theme.base05}"
    foreground_alt = "${theme.base06}"
    subtle         = "${theme.base03}"
    comment        = "${theme.softNeutral}"
    comment_dim    = "${theme.dimNeutral}"
    red            = "${theme.base08}"
    orange         = "${theme.base09}"
    yellow         = "${theme.base0A}"
    green          = "${theme.base0B}"
    aqua           = "${theme.base0C}"
    blue           = "${theme.base0D}"
    purple         = "${theme.base0E}"
    brown          = "${theme.base0F}"
    accent_surface = "${theme.primarySurface}"
    border         = "${theme.inactiveBorder}"

    [ui]
    accent             = { fg = "yellow" }
    active             = { fg = "yellow" }
    assistant          = { fg = "foreground" }
    assistant_prefix   = { fg = "yellow" }
    code_block         = { fg = "foreground" }
    cursor             = { fg = "background", bg = "yellow" }
    diff_line_nr       = { fg = "comment_dim" }
    diff_new           = { bg = "#20291d" }
    diff_new_emphasis  = { bg = "#2f3d27" }
    diff_old           = { bg = "#321d1b" }
    diff_old_emphasis  = { bg = "#4a2b27" }
    error              = { fg = "red" }
    horizontal_rule    = { fg = "comment_dim" }
    input_border       = { fg = "border" }
    input_placeholder  = { fg = "comment_dim" }
    item               = { fg = "blue" }
    item_desc          = { fg = "comment" }
    item_selected      = { fg = "yellow", bg = "accent_surface" }
    keybind_desc       = { fg = "foreground" }
    keybind_key        = { fg = "aqua", modifiers = ["bold"] }
    keybind_section    = { fg = "blue", modifiers = ["bold"] }
    panel_border       = { fg = "subtle" }
    panel_title        = { fg = "blue", modifiers = ["bold"] }
    plan_path          = { fg = "yellow", modifiers = ["bold"] }
    plan_rule          = { fg = "yellow", modifiers = ["bold"] }
    queue              = { fg = "purple" }
    queue_delete       = { fg = "red", modifiers = ["bold"] }
    spinner            = { fg = "yellow" }
    status_dim         = { fg = "comment" }
    status_notice      = { fg = "yellow" }
    status_retry_error = { fg = "red" }
    status_retry_info  = { fg = "comment" }
    strikethrough      = { fg = "comment", modifiers = ["crossed_out"] }
    table_border       = { fg = "comment_dim" }
    thinking           = { fg = "comment", modifiers = ["italic"] }
    timestamp          = { fg = "comment_dim" }
    todo_cancelled     = { fg = "red", modifiers = ["crossed_out"] }
    todo_completed     = { fg = "green" }
    todo_in_progress   = { fg = "yellow" }
    todo_pending       = { fg = "comment" }
    tool               = { fg = "foreground" }
    tool_annotation    = { fg = "comment" }
    tool_bg            = { bg = "${theme.base01}" }
    tool_dim           = { fg = "comment" }
    tool_error         = { fg = "red" }
    tool_path          = { fg = "blue" }
    tool_prefix        = { fg = "blue", modifiers = ["bold"] }
    tool_success       = { fg = "green" }
    user               = { fg = "foreground_alt" }
  '';

  runtimePackages = [
    pkgs.git
    pkgs.ripgrep
    pkgs.fd
    pkgs.jq
    pkgs.ast-grep
  ]
  ++ lib.optional cfg.enableRtk pkgs.rtk
  ++ lib.optionals cfg.enableRv [
    rv
    pkgs.difftastic
  ]
  ++ cfg.extraPackages;

  initLuaFile = pkgs.concatTextFile {
    name = "maki-init.lua";
    files = [
      cfg.initLua
    ]
    ++ lib.optional cfg.enableRoles (
      pkgs.writeText "maki-roles-require.lua" ''
        -- Loaded from ~/.config/maki/lua/roles.lua by the Home Manager module.
        require("roles").setup({ profile = ${builtins.toJSON cfg.roleProfile} })
      ''
    )
    ++ lib.optional cfg.enableRv (
      pkgs.writeText "maki-rv-require.lua" ''
        -- Loaded from ~/.config/maki/lua/rv.lua by the Home Manager module.
        require("rv")
      ''
    )
    ++ lib.optional (cfg.extraLua != "") (pkgs.writeText "maki-extra.lua" cfg.extraLua);
  };

  # PATH is suffixed, not prefixed, so a direnv or project toolchain still wins
  # for the tools a repository pins itself.
  makiWrapped = pkgs.symlinkJoin {
    name = "maki-${lib.getVersion cfg.package}";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      rm "$out/bin/maki"
      makeWrapper "${cfg.package}/bin/maki" "$out/bin/maki" \
        --suffix PATH : ${lib.escapeShellArg (lib.makeBinPath runtimePackages)}
    '';
    meta = (cfg.package.meta or { }) // {
      mainProgram = "maki";
    };
  };

  seedFile = target: source: ''
    if [[ ! -e ${lib.escapeShellArg target} ]]; then
      run install -Dm600 ${source} ${lib.escapeShellArg target}
    fi
  '';
in
{
  options.cb.maki = {
    enable = lib.mkEnableOption "Chetan's Maki coding agent configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.maki;
      defaultText = lib.literalExpression "pkgs.maki";
      description = "Maki package to install. Not in nixpkgs; this flake takes it from github:tontinton/maki through an overlay.";
    };

    initLua = lib.mkOption {
      type = lib.types.path;
      default = configDir + "/init.lua";
      description = "File providing the single `maki.setup()` call and the base plugin wiring.";
    };

    extraLua = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Lua appended after `initLua`. `maki.setup()` may only be called once,
        so use this for keymaps, commands and slots rather than settings.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages appended to the PATH Maki and its tools see.";
    };

    enableRtk = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Put rtk on Maki's PATH so it rewrites bash commands and trims their output.";
    };

    enableRoles = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Load the delegation-roles plugin: a `role` tool with scout,
        researcher, reviewer, oracle and worker, plus the `/profile` and
        `/roles` commands.
      '';
    };

    roleProfile = lib.mkOption {
      type = lib.types.enum [
        "simple"
        "complex"
        "max"
      ];
      default = "max";
      description = ''
        Delegation profile a session starts on: the model tier and reasoning
        effort each role gets. `/profile` overrides it live.
      '';
    };

    enableRv = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install rv, the local Jujutsu code reviewer, and load the Lua plugin
        that turns a review into the agent's task list.
      '';
    };

    writableRuntimeConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Seed `permissions.toml` and `providers.toml` on first activation and
        then leave them alone, so Maki's own "always allow globally" and the
        plan and base-URL choices `maki auth login` records keep working. Set
        to false to project them read-only from the store instead, which makes
        those in-app writes fail.
      '';
    };

    installTheme = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the shared Gruvbox Night palette as a Maki theme.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Only the wrapper reaches the user profile. Everything in
    # `runtimePackages` is already on the PATH it hands to Maki and to the MCP
    # servers and shell commands Maki spawns.
    home.packages = [ makiWrapped ];

    home.file = {
      # Maki never writes these, so a read-only store symlink is safe and a
      # rebuild is the only way they change.
      ".config/maki/init.lua".source = initLuaFile;
      ".config/maki/plugin.toml".source = configDir + "/plugin.toml";
      ".config/maki/AGENTS.md".source = configDir + "/AGENTS.md";

      # `recursive` links each file individually, leaving the directory itself
      # writable so a project or a later rebuild can add entries.
      ".config/maki/commands" = {
        source = configDir + "/commands";
        recursive = true;
      };
      ".config/maki/skills" = {
        source = configDir + "/skills";
        recursive = true;
      };
    }
    // lib.optionalAttrs cfg.enableRoles {
      ".config/maki/lua/roles.lua".source = configDir + "/lua/roles.lua";
    }
    // lib.optionalAttrs cfg.enableRv {
      ".config/maki/lua/rv.lua".source = configDir + "/lua/rv.lua";
    }
    // lib.optionalAttrs cfg.installTheme {
      ".config/maki/themes/gruvbox-night.toml".source = gruvboxNightTheme;
    }
    // lib.optionalAttrs (!cfg.writableRuntimeConfig) {
      ".config/maki/permissions.toml".source = configDir + "/permissions.toml";
      ".config/maki/providers.toml".source = configDir + "/providers.toml";
    };

    home.activation.makiRuntimeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      ''
        run mkdir -p ${lib.escapeShellArg makiConfigHome}

        # `~/.maki` is a legacy fallback Maki prefers over the XDG paths this
        # module manages, so everything here would be silently ignored.
        if [[ -e ${lib.escapeShellArg (config.home.homeDirectory + "/.maki")} ]]; then
          warnEcho "~/.maki exists and shadows ~/.config/maki; run 'maki migrate xdg' and remove it."
        fi
      ''
      + lib.optionalString cfg.writableRuntimeConfig (
        seedFile (makiConfigHome + "/permissions.toml") (configDir + "/permissions.toml")
        + seedFile (makiConfigHome + "/providers.toml") (configDir + "/providers.toml")
      )
    );
  };
}
