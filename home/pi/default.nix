{ ... }:
{
  imports = [ ../../modules/homeManager/pi.nix ];

  cb.pi = {
    enable = true;
    # Keep reviewed portable policy authoritative on every repository host.
    forceApplyOnActivation = true;
    enableWeb = true;
  };
}
