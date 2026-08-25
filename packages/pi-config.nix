{
  lib,
  nodejs,
  python3,
  writeShellApplication,
}:

writeShellApplication {
  name = "pi-config";
  runtimeInputs = [
    nodejs
    python3
  ];
  text = ''
    export PI_CONFIG_SNAPSHOT=${../home/pi/config}
    exec ${lib.getExe python3} ${../home/pi/pi_config.py} "$@"
  '';
  meta = {
    description = "Reconcile writable Pi configuration with a Nix flake snapshot";
    license = lib.licenses.mit;
    mainProgram = "pi-config";
    platforms = lib.platforms.unix;
  };
}
