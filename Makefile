host?=hugh

build-darwin:
	nix build .#darwinConfigurations.$(host).system --show-trace

apply-darwin: build-darwin
	result/sw/bin/darwin-rebuild switch --flake .#$(host)
