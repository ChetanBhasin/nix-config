#!/usr/bin/env zsh
# macOS (Darwin) specific shell configuration

# ===============================================
# macOS SDK CONFIGURATION
# ===============================================

export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion | cut -d. -f1-2)"

# Compiler settings for Darwin
export CC="clang"
export CXX="clang++"

# ===============================================
# HOMEBREW ENV
# ===============================================

if [[ -x /opt/homebrew/bin/brew ]]; then
  # Ensure Homebrew packages are available in PATH/man/Info
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# ===============================================
# CLIPBOARD INTEGRATION
# ===============================================

# FZF history widget - copy to macOS clipboard
export FZF_CTRL_R_OPTS="${FZF_CTRL_R_OPTS} --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'"

# ===============================================
# DARWIN-SPECIFIC FUNCTIONS
# ===============================================

# Run a command in a Nix shell that includes Rust packages (macOS)
nrr() {
  nix-shell -p openssl libiconv pkg-config apple-sdk_15 --run "$*"
}

# Run cargo with arguments in a Nix shell (macOS)
nrc() {
  nix-shell -p openssl libiconv pkg-config apple-sdk_15 --run "cargo $@"
}

# ===============================================
# HOMEBREW CLEANUP (macOS only)
# ===============================================

alias cleanup="brew cleanup && brew doctor && nix-collect-garbage"
