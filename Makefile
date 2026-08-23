host?=
node?=
darwin_host?=$(or $(host),hugh)
nixos_host?=$(or $(node),$(host),boris)
open_files_limit?=65536

build-darwin:
	ulimit -n $(open_files_limit); nix build .#darwinConfigurations.$(darwin_host).system

apply-darwin: build-darwin
	ulimit -n $(open_files_limit); sudo -H result/sw/bin/darwin-rebuild switch --flake .#$(darwin_host)

build-nixos:
	ulimit -n $(open_files_limit); nix build .#nixosConfigurations.$(nixos_host).config.system.build.toplevel

apply-nixos:
	ulimit -n $(open_files_limit); sudo nixos-rebuild switch --flake .#$(nixos_host)

apply-nix: apply-nixos
