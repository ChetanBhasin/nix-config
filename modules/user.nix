{ inputs, ... }:
{
  flake.modules.darwin.user = {
    imports = [ inputs.home-manager.darwinModules.home-manager ];
    users.users.chetan.home = "/Users/chetan";
    home-manager = {
      useGlobalPkgs = true;
    };
  };
  flake.modules.nixos.user = { pkgs, ... }: {
    imports = [ inputs.home-manager.nixosModules.home-manager ];
    users.users.chetan = {
      home = "/home/chetan";
      isNormalUser = true;
      group = "chetan";
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
    };
    users.groups.chetan = { };
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
    };
  };
}
