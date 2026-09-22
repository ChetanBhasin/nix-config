{ ... }:
{
  imports = [ ../../modules/homeManager/maki.nix ];

  # The configured coding agent: shared Gruvbox Night palette, a small context
  # footprint per turn.
  cb.maki.enable = true;

  # Goal mode: /goal keeps the agent working across turns using Maki's Lua
  # plugin APIs.
  cb.maki.enableGoal = true;
}
