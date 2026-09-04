# Standalone Helix module for Home Manager.
# Can be imported via: inputs.nix-config.homeManagerModules.helix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.cb.helix;
  theme = import ../theme/luna.nix;
  bazelLsp = pkgs.callPackage ../../packages/bazel-lsp.nix { };
  rustGlancer = pkgs.callPackage ../../packages/rust-glancer.nix { };
  rustServerPackage = if cfg.rustLsp == "rust-glancer" then rustGlancer else pkgs.rust-analyzer;

  rustLanguage = {
    name = "rust";
    language-servers = [ cfg.rustLsp ];
    auto-format = true;
  };

  ruffHelixFormat = pkgs.writeShellApplication {
    name = "ruff-helix-format";
    runtimeInputs = [ pkgs.ruff ];
    text = ''
      filename="''${1:-stdin.py}"
      ruff check --quiet --select I --fix --stdin-filename "$filename" - \
        | ruff format --quiet --stdin-filename "$filename" -
    '';
  };
in
{
  options.cb.helix = {
    enable = lib.mkEnableOption "Chetan's Helix configuration";

    defaultEditor = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set Helix as the default editor";
    };

    rustLsp = lib.mkOption {
      type = lib.types.enum [
        "rust-analyzer"
        "rust-glancer"
      ];
      default = "rust-glancer";
      description = "Which Rust language server Helix should use for `.rs` files.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages to add to Helix's PATH";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.helix = {
      enable = true;
      package = pkgs.helix;
      defaultEditor = cfg.defaultEditor;

      extraPackages =
        with pkgs;
        [
          # Rust
          rustServerPackage
          rustfmt

          # Nix
          nixd
          nixfmt

          # Python
          basedpyright
          ruff
          ruffHelixFormat

          # TypeScript and JavaScript
          typescript-language-server

          # Go
          gopls

          # Lua
          lua-language-server
          stylua

          # Bash, JSON, YAML, Dockerfile, Kotlin, AWK, and Just
          bash-language-server
          vscode-langservers-extracted
          yaml-language-server
          dockerfile-language-server
          kotlin-language-server
          awk-language-server
          gawk
          just-lsp
          just

          # Bazel and Starlark
          bazelLsp
          bazelisk
          buildifier
          efm-langserver
        ]
        ++ cfg.extraPackages;

      settings = {
        theme = theme.name;

        editor = {
          default-yank-register = "+";
          line-number = "relative";
          scrolloff = 8;
          mouse = true;
          text-width = 120;
          rulers = [ 120 ];
          bufferline = "multiple";
          gutters = [
            "diagnostics"
            "line-numbers"
            "spacer"
            "diff"
          ];
          popup-border = "all";
          end-of-line-diagnostics = "warning";
          auto-completion = true;
          path-completion = true;

          soft-wrap.enable = false;

          indent-guides = {
            render = true;
            character = "│";
            skip-levels = 1;
          };

          cursor-shape = {
            normal = "block";
            insert = "bar";
            select = "underline";
          };

          lsp = {
            enable = true;
            display-messages = true;
            auto-signature-help = true;
            display-signature-help-docs = false;
            display-inlay-hints = true;
          };

          statusline = {
            left = [
              "mode"
              "spinner"
              "file-name"
              "file-modification-indicator"
              "version-control"
            ];
            center = [ ];
            right = [
              "diagnostics"
              "selections"
              "position"
              "file-type"
            ];
            diagnostics = [
              "warning"
              "error"
            ];
          };
        };

        keys.normal = {
          "C-p" = "command_palette";
          space."?" = "no_op";
          # Zellij owns bare C-h/j/k/l. Helix's native C-w window mode keeps
          # plain h/j/k/l available for moving between internal views.
        };
      };

      themes.${theme.name} = {
        inherits = "base16_default_dark";

        # Keep comments calm in low light and make editor surfaces distinct
        # without putting saturated accents behind ordinary text.
        "comment" = {
          fg = "base03";
          modifiers = [ "italic" ];
        };
        "ui.background" = {
          bg = "base00";
        };
        "ui.window" = {
          fg = "inactive-border";
        };
        "ui.menu.selected" = {
          fg = "base06";
          bg = "base02";
          modifiers = [ "bold" ];
        };
        "ui.statusline.normal" = {
          fg = "base05";
          bg = "base01";
          modifiers = [ "bold" ];
        };
        "ui.statusline.insert" = {
          fg = "base00";
          bg = "base0D";
          modifiers = [ "bold" ];
        };
        "ui.statusline.select" = {
          fg = "base00";
          bg = "base09";
          modifiers = [ "bold" ];
        };

        "diagnostic.error".underline = {
          color = "base08";
          style = "curl";
        };
        "diagnostic.warning".underline = {
          color = "base0A";
          style = "curl";
        };
        "diagnostic.info".underline = {
          color = "base0C";
          style = "curl";
        };
        "diagnostic.hint".underline = {
          color = "base0F";
          style = "curl";
        };

        palette = {
          inherit (theme)
            base00
            base01
            base02
            base03
            base04
            base05
            base06
            base07
            base08
            base09
            base0A
            base0B
            base0C
            base0D
            base0E
            base0F
            ;
          "active-border" = theme.activeBorder;
          "inactive-border" = theme.inactiveBorder;
        };
      };

      languages = {
        language-server = {
          basedpyright = {
            command = "basedpyright-langserver";
            args = [ "--stdio" ];
            config.basedpyright.analysis = {
              typeCheckingMode = "standard";
              autoSearchPaths = true;
              useLibraryCodeForTypes = true;
              diagnosticMode = "openFilesOnly";
              inlayHints = {
                variableTypes = true;
                functionReturnTypes = true;
                callArgumentNames = true;
              };
            };
          };

          ruff = {
            command = "ruff";
            args = [ "server" ];
          };

          bazel-lsp = {
            command = "bazel-lsp";
            args = [
              "--bazel"
              "bazelisk"
            ];
          };

          efm-buildifier = {
            command = "efm-langserver";
            config.languages.starlark = [
              {
                lintCommand = "buildifier -mode=check -lint=warn -path='\${INPUT}'";
                lintStdin = true;
                lintFormats = [
                  "%f:%l:%c: %m"
                  "%f:%l: %m"
                ];
                lintSeverity = 2;
                lintSource = "buildifier";
                lintAfterOpen = true;
                rootMarkers = [
                  "MODULE.bazel"
                  "WORKSPACE.bazel"
                  "WORKSPACE"
                ];
                requireMarker = true;
              }
            ];
          };

          rust-analyzer = {
            command = "rust-analyzer";
            config = {
              checkOnSave = false;
              check = {
                command = "check";
                extraArgs = [ "--message-format=json" ];
              };
              cargo = {
                allFeatures = false;
                loadOutDirsFromCheck = false;
                runBuildScripts = false;
                noDefaultFeatures = false;
              };
              procMacro = {
                enable = true;
                attributes.enable = true;
              };
              inlayHints = {
                bindingModeHints.enable = false;
                chainingHints.enable = true;
                closingBraceHints = {
                  enable = true;
                  minLines = 25;
                };
                closureReturnTypeHints.enable = "never";
                lifetimeElisionHints = {
                  enable = "never";
                  useParameterNames = false;
                };
                maxLength = 25;
                parameterHints.enable = true;
                reborrowHints.enable = "never";
                renderColons = true;
                typeHints = {
                  enable = true;
                  hideClosureInitialization = false;
                  hideNamedConstructor = false;
                };
              };
              completion.callable.snippets = "fill_arguments";
            };
          };

          rust-glancer = {
            command = "rust-glancer";
            args = [ "lsp" ];
          };

          typescript-language-server = {
            command = "typescript-language-server";
            args = [ "--stdio" ];
            config = {
              hostInfo = "helix";
              typescript.inlayHints = {
                includeInlayParameterNameHints = "all";
                includeInlayParameterNameHintsWhenArgumentMatchesName = false;
                includeInlayFunctionParameterTypeHints = true;
                includeInlayVariableTypeHints = true;
                includeInlayVariableTypeHintsWhenTypeMatchesName = false;
                includeInlayPropertyDeclarationTypeHints = true;
                includeInlayFunctionLikeReturnTypeHints = true;
                includeInlayEnumMemberValueHints = true;
              };
              javascript.inlayHints = {
                includeInlayParameterNameHints = "all";
                includeInlayParameterNameHintsWhenArgumentMatchesName = false;
                includeInlayFunctionParameterTypeHints = true;
                includeInlayVariableTypeHints = true;
                includeInlayVariableTypeHintsWhenTypeMatchesName = false;
                includeInlayPropertyDeclarationTypeHints = true;
                includeInlayFunctionLikeReturnTypeHints = true;
                includeInlayEnumMemberValueHints = true;
              };
            };
          };

          gopls = {
            command = "gopls";
            config.hints = {
              assignVariableTypes = true;
              compositeLiteralFields = true;
              compositeLiteralTypes = true;
              constantValues = true;
              functionTypeParameters = true;
              parameterNames = true;
              rangeVariableTypes = true;
            };
          };

          lua-language-server = {
            command = "lua-language-server";
            config.Lua.hint = {
              enable = true;
              setType = false;
              paramType = true;
              paramName = "Disable";
              semicolon = "Disable";
              arrayIndex = "Disable";
            };
          };
        };

        language = [
          rustLanguage
          {
            name = "nix";
            language-servers = [ "nixd" ];
            formatter = {
              command = "nixfmt";
              args = [ "-" ];
            };
            auto-format = true;
          }
          {
            name = "python";
            language-servers = [
              {
                name = "basedpyright";
                except-features = [
                  "code-action"
                  "format"
                ];
              }
              {
                name = "ruff";
                only-features = [
                  "code-action"
                  "diagnostics"
                ];
              }
            ];
            formatter = {
              command = "ruff-helix-format";
              args = [ "%{buffer_name}" ];
            };
            auto-format = true;
          }
          {
            name = "javascript";
            language-servers = [ "typescript-language-server" ];
          }
          {
            name = "jsx";
            language-servers = [ "typescript-language-server" ];
          }
          {
            name = "typescript";
            language-servers = [ "typescript-language-server" ];
          }
          {
            name = "tsx";
            language-servers = [ "typescript-language-server" ];
          }
          {
            name = "go";
            language-servers = [ "gopls" ];
            auto-format = true;
          }
          {
            name = "lua";
            language-servers = [ "lua-language-server" ];
            formatter = {
              command = "stylua";
              args = [ "-" ];
            };
            auto-format = true;
          }
          {
            name = "bash";
            language-servers = [ "bash-language-server" ];
          }
          {
            name = "json";
            language-servers = [ "vscode-json-language-server" ];
            auto-format = true;
          }
          {
            name = "jsonc";
            language-servers = [ "vscode-json-language-server" ];
            auto-format = true;
          }
          {
            name = "yaml";
            language-servers = [ "yaml-language-server" ];
          }
          {
            name = "dockerfile";
            language-servers = [ "docker-langserver" ];
          }
          {
            name = "kotlin";
            language-servers = [ "kotlin-language-server" ];
          }
          {
            name = "awk";
            language-servers = [ "awk-language-server" ];
            formatter = {
              command = "gawk";
              args = [
                "-f"
                "-"
                "-o-"
              ];
            };
            auto-format = true;
          }
          {
            name = "just";
            language-servers = [ "just-lsp" ];
            formatter = {
              command = "just";
              args = [
                "--fmt"
                "--justfile"
                "-"
              ];
            };
            auto-format = true;
          }
          {
            name = "starlark";
            language-id = "starlark";
            language-servers = [
              "bazel-lsp"
              {
                name = "efm-buildifier";
                only-features = [ "diagnostics" ];
              }
            ];
            roots = [
              "MODULE.bazel"
              "WORKSPACE.bazel"
              "WORKSPACE"
            ];
            formatter = {
              command = "buildifier";
              args = [ "-path=%{buffer_name}" ];
            };
            auto-format = true;
          }
        ];
      };
    };
  };
}
