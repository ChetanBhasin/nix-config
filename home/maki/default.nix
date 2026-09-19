{ ... }:
{
  imports = [ ../../modules/homeManager/maki.nix ];

  # The configured coding agent: shared Gruvbox Night palette, a small context
  # footprint per turn.
  cb.maki.enable = true;

  # Goal mode: /goal keeps the agent working across turns. It calls the
  # fork's plugin-platform APIs, so the maki input must carry that branch.
  cb.maki.enableGoal = true;
}
