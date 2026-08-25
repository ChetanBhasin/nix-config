# Home Manager Modules Index
# Exports individual modules and a combined default module
#
# Usage in other flakes:
#   inputs.nix-config.homeManagerModules.helix    # Just helix
#   inputs.nix-config.homeManagerModules.neovim   # Just neovim
#   inputs.nix-config.homeManagerModules.terminal # Just terminal (zsh, fzf, starship, etc.)
#   inputs.nix-config.homeManagerModules.tmux     # Just tmux
#   inputs.nix-config.homeManagerModules.zellij   # Just zellij
#   inputs.nix-config.homeManagerModules.pi       # Just Pi Coding Agent
#   inputs.nix-config.homeManagerModules.default  # All modules combined
{
  # Individual modules
  helix = import ./helix.nix;
  neovim = import ./neovim.nix;
  terminal = import ./terminal.nix;
  tmux = import ./tmux.nix;
  zellij = import ./zellij.nix;
  pi = import ./pi.nix;

  # Combined module that imports all
  default = { ... }: {
    imports = [
      ./helix.nix
      ./neovim.nix
      ./terminal.nix
      ./tmux.nix
      ./zellij.nix
      ./pi.nix
    ];
  };
}
