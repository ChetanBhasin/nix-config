{ config, lib, ... }:
let
  modules = config.flake.modules.homeManager;
in
{
  # flake-parts declares NixOS outputs; give Darwin hosts the same merge behavior.
  options.flake.darwinConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "nix-darwin host configurations.";
  };

  config.flake.homeManagerModules = {
    inherit (modules)
      neovim
      terminal
      tmux
      ;
    default = {
      imports = [
        modules.neovim
        modules.terminal
        modules.tmux
      ];
    };
  };
}
