{ ... }:
{
  imports = [ ../../modules/homeManager/zellij.nix ];

  # Zellij is an opt-in trial. Tmux remains the default multiplexer.
  cb.zellij.enable = true;
}
