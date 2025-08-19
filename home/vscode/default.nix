{ config, pkgs, ... }: {
  programs.vscode = {
    enable = true;
    mutableExtensionsDir = true;
    profiles.default.enableExtensionUpdateCheck = true;
    profiles.default.enableUpdateCheck = true;
    profiles.default.extensions = with pkgs.vscode-extensions;
      [
        ms-azuretools.vscode-docker
        vscodevim.vim
        mkhl.direnv
        jnoortheen.nix-ide
        brettm12345.nixfmt-vscode
        ms-vscode-remote.remote-ssh
        yzhang.markdown-all-in-one
        svelte.svelte-vscode
        streetsidesoftware.code-spell-checker
        serayuzgur.crates
        sumneko.lua
      ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [{
        name = "vscode-icons";
        publisher = "vscode-icons-team";
        version = "12.2.0";
        sha256 = "PxM+20mkj7DpcdFuExUFN5wldfs7Qmas3CnZpEFeRYs=";
      }];
  };
}
