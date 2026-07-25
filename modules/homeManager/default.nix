# Home Manager Modules Index
# Exports individual modules and a combined default module
#
# Usage in other flakes:
#   inputs.nix-config.homeManagerModules.neovim   # Just neovim
#   inputs.nix-config.homeManagerModules.terminal # Just terminal (zsh, fzf, starship, etc.)
#   inputs.nix-config.homeManagerModules.tmux     # Just tmux
#   inputs.nix-config.homeManagerModules.default  # All modules combined
{
  # Individual modules
  neovim = import ./neovim.nix;
  terminal = import ./terminal.nix;
  tmux = import ./tmux.nix;

  # Combined module that imports all
  default = { ... }: {
    imports = [
      ./neovim.nix
      ./terminal.nix
      ./tmux.nix
    ];
  };
}
