{
  flake.modules.homeManager.personal-app-themes =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      supportDir =
        if pkgs.stdenv.hostPlatform.isDarwin then
          "${config.home.homeDirectory}/Library/Application Support"
        else
          config.xdg.configHome;
      lazygitFile = "${
        if pkgs.stdenv.hostPlatform.isDarwin && !config.xdg.enable then
          "Library/Application Support"
        else
          config.xdg.configHome
      }/lazygit/config.yml";
      lazygitPath =
        if lib.hasPrefix "/" lazygitFile then
          lazygitFile
        else
          "${config.home.homeDirectory}/${lazygitFile}";
      lazygitTheme =
        (pkgs.formats.yaml { }).generate "lazygit-stylix.yml"
          config.programs.lazygit.settings;
      snippetName = "chetan-stylix";
      snippetMarker = "/* Managed by nix-config: Stylix colors. */";
      obsidianCss = pkgs.writeText "${snippetName}.css" (
        snippetMarker
        + "\n"
        + lib.concatMapStringsSep "\n" (
          snippet: snippet.text
        ) config.programs.obsidian.defaultSettings.cssSnippets
      );
    in
    {
      programs.lazygit = {
        enable = true;
        settings.gui.theme.selectedLineBgColor = lib.mkForce [ config.lib.stylix.palette.primarySurface ];
      };
      # LazyGit may write its primary config; the generated theme is a second file.
      home.file.${lazygitFile}.enable = lib.mkForce false;
      programs.k9s = {
        enable = true;
        settings = lib.mkForce { };
      };
      programs.zed-editor = {
        enable = true;
        # Keep Zed's writable JSONC settings, including font preferences, app-owned.
        userSettings = lib.mkForce { };
      };
      # Only consume Stylix's CSS; Home Manager must not manage vault settings.
      programs.obsidian.enable = false;
      stylix.targets = {
        lazygit.enable = true;
        k9s.enable = true;
        zed = {
          enable = true;
          fonts.enable = false;
          colors.override = (config.stylix.base16.mkSchemeAttrs config.stylix.base16Scheme).override (
            config.stylix.override
            // {
              scheme = "Chetan";
              slug = "chetan";
            }
          );
        };
        obsidian = {
          enable = true;
          fonts.enable = false;
        };
      };
      home.sessionVariables = {
        LG_CONFIG_FILE = "${lazygitPath},${lazygitTheme}";
        K9S_SKIN = "stylix";
      };
      xdg.configFile."obsidian/snippets/${snippetName}.css".source = obsidianCss;

      home.activation.personalAppThemes = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run ${pkgs.python3}/bin/python3 - ${
          lib.escapeShellArgs [
            lazygitPath
            "${config.xdg.configHome}/zed/settings.json"
            "${supportDir}/obsidian/obsidian.json"
            (toString obsidianCss)
          ]
        } <<'PY'
        import json
        import os
        import sys
        from pathlib import Path

        def seed(path, settings):
            path.parent.mkdir(parents=True, exist_ok=True)
            try:
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            except FileExistsError:
                return
            with os.fdopen(fd, "w") as target:
                json.dump(settings, target, indent=2)
                target.write("\n")

        lazygit, zed, registry, source = map(Path, sys.argv[1:])
        seed(lazygit, {})
        seed(zed, {"theme": "Base16 Chetan"})
        if registry.exists():
            css = source.read_text()
            for vault in json.loads(registry.read_text()).get("vaults", {}).values():
                root = Path(vault["path"])
                if not root.is_dir():
                    continue
                target = root / ".obsidian/snippets/${snippetName}.css"
                if target.is_symlink() or (target.exists() and not target.read_text().startswith(${builtins.toJSON snippetMarker})):
                    print(f"Keeping existing unowned Obsidian snippet: {target}")
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(css)
                seed(root / ".obsidian/appearance.json", {"enabledCssSnippets": ["${snippetName}"]})
        PY
      '';
    };
}
