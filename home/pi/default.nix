{ ... }:
{
  imports = [ ../../modules/homeManager/pi.nix ];

  cb.pi = {
    enable = true;
    enableWeb = true;
  };
}
