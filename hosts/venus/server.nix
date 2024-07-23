{ self, pkgs, lib, ... }: {
  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;

      dockerCompat = true;

      defaultNetwork.settings.dns_enabled = true;
    };
  };
  virtualisation.containers.containersConf.settings = {
    # podman seems to not work with systemd-resolved
    containers.dns_servers = [ "8.8.8.8" "8.8.4.4" ];
  };

  # Useful otherdevelopment tools
  environment.systemPackages = with pkgs; [
    podman-tui # status of containers in the terminal
    docker-compose # start group of containers for dev
    podman-compose # start group of containers for dev
  ];

}
