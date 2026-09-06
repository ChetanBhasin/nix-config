{ pkgs }:

# Pin upstream's full-frame pane border work until it lands in a tmux release.
# PR: https://github.com/tmux/tmux/pull/5433
# Source/security updates from nixpkgs do not flow through this pin; review it regularly.
pkgs.tmux.overrideAttrs (old: {
  version = "next-3.8";

  src = pkgs.fetchFromGitHub {
    owner = "tmux";
    repo = "tmux";
    rev = "fe8f9ff526abbf141533d1f63402933065205c4c";
    hash = "sha256-3qSBVMSf+El7lkxgGQtvcRpRYKgD2QyNz5mTzGf04Ik=";
  };

  # tmux supports rounded popup/menu borders, but not rounded pane borders.
  # Reuse its existing rounded glyph map for pane frames as a small downstream patch.
  patches = (old.patches or [ ]) ++ [ ./tmux-rounded-pane-borders.patch ];

  meta = old.meta // {
    changelog = "https://github.com/tmux/tmux/pull/5433";
  };
})
