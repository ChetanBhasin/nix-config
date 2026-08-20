{ ... }:
{
  imports = [ ../../modules/homeManager/helix.nix ];

  # Helix is an opt-in side-by-side trial. NeoVim remains the default editor.
  cb.helix.enable = true;
}
