{ ... }:
{
  imports = [ ../../modules/homeManager/maki.nix ];

  # Maki runs alongside Pi rather than replacing it: same palette, same
  # operating contract, a much smaller context footprint per turn.
  cb.maki.enable = true;
}
