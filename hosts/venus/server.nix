{ pkgs, lib, ... }: {
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

  ## Gitea installation
  services.nginx.virtualHosts."git.venus.panther-ling.ts.net" = {
    enableACME = false;
    forceSSL = false;
    locations."/" = { proxyPass = "http://localhost:3001/"; };
  };

  services.postgresql = {
    ensureDatabases = [ "gitea" ];
    ensureUsers = [{ name = "gitea"; }];
  };

  services.gitea = {
    enable = true;
    appName = "My awesome Gitea server"; # Give the site a name
    database = { type = "postgres"; };
    domain = "git.lorcanservices.com";
    rootUrl = "https://git.lorcanservices.com";
    settings.server.ROOT_URL = "https://git.lorcanservices.com";
    settings.server.SSH_DOMAIN = "git-ssh.lorcanservices.com";
    httpPort = 3001;
  };

  services.cloudflared = {
    enable = true;
    tunnels = {
      "f57bfb1a-b6c7-4201-b80e-e0d45aa6709a" = {
        credentialsFile =
          "/home/cloudflared/.cloudflared/f57bfb1a-b6c7-4201-b80e-e0d45aa6709a.json";
        default = "http_status:404";
        ingress = {
          "git.lorcanservices.com" = { service = "http://localhost:3001"; };
          "git-ssh.lorcanservices.com" = { service = "ssh://localhost:22"; };
        };
      };
    };
  };
}
