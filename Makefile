host?=hugh
open_files_limit?=65536

build-darwin:
	ulimit -n $(open_files_limit); nix build .#darwinConfigurations.$(host).system

apply-darwin: build-darwin
	ulimit -n $(open_files_limit); sudo -H result/sw/bin/darwin-rebuild switch --flake .#$(host)

build-nixos:
	ulimit -n $(open_files_limit); nix build .#nixosConfigurations.$(host).config.system.build.toplevel

apply-nixos:
	ulimit -n $(open_files_limit); sudo nixos-rebuild switch --flake .#$(host)

apply-nix: apply-nixos
