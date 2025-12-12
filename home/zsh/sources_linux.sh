#!/usr/bin/env zsh
# Linux specific shell configuration

# ===============================================
# CLIPBOARD INTEGRATION
# ===============================================

# Detect clipboard command (wayland vs x11)
if [[ -n "$WAYLAND_DISPLAY" ]]; then
  CLIPBOARD_CMD="wl-copy"
elif [[ -n "$DISPLAY" ]]; then
  CLIPBOARD_CMD="xclip -selection clipboard"
else
  CLIPBOARD_CMD="cat" # fallback for headless
fi

# FZF history widget - copy to Linux clipboard
export FZF_CTRL_R_OPTS="${FZF_CTRL_R_OPTS} --bind 'ctrl-y:execute-silent(echo -n {2..} | ${CLIPBOARD_CMD})+abort'"

# ===============================================
# LINUX-SPECIFIC FUNCTIONS
# ===============================================

# Run a command in a Nix shell that includes Rust packages (Linux)
nrr() {
  nix-shell -p openssl pkg-config --run "$*"
}

# Run cargo with arguments in a Nix shell (Linux)
nrc() {
  nix-shell -p openssl pkg-config --run "cargo $@"
}

# ===============================================
# LINUX CLEANUP
# ===============================================

alias cleanup="nix-collect-garbage"
