host?=hugh

build-darwin:
	nix build .#darwinConfigurations.$(host).system

apply-darwin: build-darwin
	result/sw/bin/darwin-rebuild switch --flake .#$(host)

apply-nix:
	nix-rebuild switch --flake .#$(host)
