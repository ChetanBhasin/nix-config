---
name: nix-host-validation
description: Use when validating NixOS, nix-darwin or Home Manager changes, especially Pi live-first capture, launcher qualification and build-versus-activation claims.
---
# Nix host validation

- Read the target repository instructions, flake outputs and actual host configuration. Identify the host/platform, affected module/package, current generation and intended observable change. Do not guess a host or apply a sibling host's configuration.
- Use Lens diagnostics before builds. Start with a focused `nix eval`, then build the relevant derivation/configuration using the repository's canonical command. Darwin changes need Darwin evaluation/build qualification; a Linux test does not establish macOS behavior. Report unavailable builders explicitly.
- A successful evaluation is not a build, and a build is not activation. Exercise the built executable or isolated service/UI path where applicable. Test relevant startup/reload/failure paths, not just derivation existence.
- For Pi configuration, change the live `~/.pi/agent` state first, run focused tests and fresh-process qualification, then `pi-config capture`. Never force-apply an older projection over uncaptured live work. Keep credentials, sessions, databases, caches and dependency trees out of captured source; do not remove a lock to force synchronization.
- For Pi launcher changes, use the repository launcher regressions with the actual built wrapper and package; include cold/partial package profiles and RPC startup when loading behavior changes. Revalidate private SDK hooks on version upgrades. Existing Pi processes retain boot-resolved settings.
- Use the [workflow ledger/lease protocol](../../extensions/auto-mode/WORKFLOW.md) for source changes and shell permits. Put build/test artifacts outside source roots or explicitly account for their fingerprint effects. Preserve the user's VCS changes and running services.
- Host activation, service restarts and reloading the live tmux server require corresponding authority and a safe process boundary. Follow `pi-config` preflight/lock errors rather than bypassing them. Never claim applied/live/end-to-end unless that exact scenario ran.
- Finish with host/platform, revision, exact checks and exit results, built artifact, activation status, rollback/reference generation where relevant, and remaining platform/user-journey gaps. Do not add CI/CD unless requested.
