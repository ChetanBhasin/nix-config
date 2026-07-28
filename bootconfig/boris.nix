# Hardware configuration detected on Boris.
#
# The LUKS mapper keeps its existing name to preserve the laptop's known-good
# boot layout while the NixOS hostname changes from Mars to Boris.
{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "thunderbolt"
    "usbhid"
    "xhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  boot.initrd.luks.devices."mars-cryptroot".device =
    "/dev/disk/by-uuid/51df36f8-ea58-46e1-ba27-c90e2f34179b";

  fileSystems = {
    "/" = {
      device = "/dev/mapper/mars-cryptroot";
      fsType = "btrfs";
      options = [ "subvol=root" ];
    };

    "/nix" = {
      device = "/dev/mapper/mars-cryptroot";
      fsType = "btrfs";
      options = [ "subvol=nix" ];
    };

    "/home" = {
      device = "/dev/mapper/mars-cryptroot";
      fsType = "btrfs";
      options = [ "subvol=home" ];
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/F6C1-2F04";
      fsType = "vfat";
      options = [
        "dmask=0022"
        "fmask=0022"
      ];
    };
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Preserve Boris's existing GRUB setup. It is installed both to the disk
  # and to the removable EFI path used by this machine's firmware.
  boot.loader.grub = {
    enable = true;
    devices = lib.mkForce [ "/dev/nvme0n1" ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  boot.loader.efi.canTouchEfiVariables = false;
}
