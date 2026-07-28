{
  config,
  lib,
  ...
}:
let
  initrdSshHostKeyPath = "/etc/secrets/initrd/ssh_host_ed25519_key";
  initrdSshHostKeySource = ../../secrets/initrd/ssh_host_ed25519_key;
  unlockAuthorizedKeys = map (
    key: ''command="systemctl default" ${key}''
  ) config.users.users.root.openssh.authorizedKeys.keys;
in
{
  # Boris uses this driver for its wired Ethernet interface.
  boot.initrd.availableKernelModules = [ "r8169" ];

  # Keep a dedicated host identity for the initrd SSH server. The private key
  # is necessarily present in the unencrypted initrd and must not be reused by
  # the regular stage-2 SSH server.
  boot.initrd.secrets.${initrdSshHostKeyPath} = lib.mkForce initrdSshHostKeySource;

  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 22;
      hostKeys = [ initrdSshHostKeyPath ];
      authorizedKeys = unlockAuthorizedKeys;
    };
  };

  # Obtain a LAN IPv4 address and a public IPv6 address from router
  # advertisements before starting the initrd SSH server.
  boot.initrd.systemd.network = {
    enable = true;
    networks."10-boris-ethernet" = {
      matchConfig.MACAddress = "58:47:ca:75:f1:06";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };
}
