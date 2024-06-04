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
    settings.actions.ENABLED = true;
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

  environment.etc."nextcloud-admin-pass".text = "thispasswordisnotsecure";

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud28;
    hostName = "venus.panther-ling.ts.net";
    config = {
      adminpassFile = "/etc/nextcloud-admin-pass";
      trustedProxies = [ "127.0.0.1" ];
    };
    extraApps = {
      inherit (pkgs.nextcloud28Packages.apps) mail calendar onlyoffice spreed;
    };
    extraAppsEnable = true;

    extraOptions.enabledPreviewProviders = [
      "OC\\Preview\\BMP"
      "OC\\Preview\\GIF"
      "OC\\Preview\\JPEG"
      "OC\\Preview\\Krita"
      "OC\\Preview\\MarkDown"
      "OC\\Preview\\MP3"
      "OC\\Preview\\OpenDocument"
      "OC\\Preview\\PNG"
      "OC\\Preview\\TXT"
      "OC\\Preview\\XBitmap"
      "OC\\Preview\\HEIC"
    ];
  };

  services.nginx.virtualHosts = {
    "venus.panther-ling.ts.net" = {
      locations."/*".proxyPass = "http://127.0.0.1";
      forceSSL = false;
      enableACME = false;
    };
  };
}
