host?=hugh
open_files_limit?=65536

build-darwin:
	ulimit -n $(open_files_limit); nix build .#darwinConfigurations.$(host).system

apply-darwin: build-darwin
	ulimit -n $(open_files_limit); result/sw/bin/darwin-rebuild switch --flake .#$(host)

apply-nix:
	ulimit -n $(open_files_limit); nix-rebuild switch --flake .#$(host)
