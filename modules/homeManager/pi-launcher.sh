#!/usr/bin/env bash
# Internal argv: unwrapped Pi, store Node, Pi package root, policy helper, caller argv.
# Environment/browser/subagent policy remains in pi.nix.
pi_binary=$1
pi_node=$2
pi_package_dir=$3
pi_policy_helper=$4
shift 4

# Pi dispatches management commands only at argv[0], before extension parsing.
# Repairs must not prevent the installation/update commands needed to fix them.
case "${1-}" in
  install|remove|uninstall|update|list|config|auth) exec "$pi_binary" "$@" ;;
esac

# Match Pi's tilde/file-URL resolution before probing the preflight location.
pi_agent_dir=$("$pi_node" "$pi_policy_helper" "$pi_package_dir" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" --resolve-agent-dir) || exit $?
# Extensions receive the same canonical directory as Pi and the preflight.
export PI_CODING_AGENT_DIR="$pi_agent_dir"
pi_patcher="$pi_agent_dir/extensions/runtime-reliability/patcher.mjs"
pi_bootstrap="$pi_agent_dir/extensions/runtime-reliability/bootstrap.mjs"
unset PI_LAUNCHER_REPAIR_BOOTSTRAP
if [[ -f "$pi_patcher" ]]; then
  # A failed repair is fatal; never corrupt JSON/RPC stdout with its report.
  if [[ -f "$pi_bootstrap" ]]; then
    "$pi_node" "$pi_patcher" --bootstrap "$pi_agent_dir" >&2 || exit $?
    # Bind the post-resolution guard to this exact decision. If it disappears,
    # the preload must fail rather than silently importing unverified packages.
    export PI_LAUNCHER_REPAIR_BOOTSTRAP="$pi_bootstrap"
  else
    # Backward compatibility: older profiles retain the strict upfront preflight.
    "$pi_node" "$pi_patcher" --apply "$pi_agent_dir" >&2 || exit $?
  fi
fi

# Apply policy to the actual loaded extension set, not a pre-trust prediction.
# Preloading the same SDK module as Pi preserves the real CLI and caller argv.
# The preload removes its private environment before Pi starts child programs.
pi_preload_uri=$("$pi_node" "$pi_policy_helper" "$pi_package_dir" "$pi_agent_dir" --preload-url) || exit $?
export PI_LAUNCHER_POLICY_PACKAGE="$pi_package_dir"
export NODE_OPTIONS="${NODE_OPTIONS-} --import=$pi_preload_uri"
exec "$pi_binary" "$@"
