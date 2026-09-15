{ ... }:
{
  imports = [ ../../modules/homeManager/maki.nix ];

  # The configured coding agent: shared Gruvbox Night palette, a small context
  # footprint per turn.
  cb.maki.enable = true;
}
