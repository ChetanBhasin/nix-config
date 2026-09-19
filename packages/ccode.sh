# ccode — claude-code with per-profile config directories.
#
# Each profile gets its own CLAUDE_CONFIG_DIR under $CCODE_HOME/profiles,
# so accounts, history, and settings stay separate.
# @DEFAULT_PROFILE@ and @CLAUDE_BIN@ are substituted by the Nix build;
# do not run this file directly.

CCODE_HOME="${CCODE_HOME:-$HOME/.ccode}"
PROFILES_DIR="$CCODE_HOME/profiles"
DEFAULT_PROFILE="@DEFAULT_PROFILE@"
CLAUDE_BIN="@CLAUDE_BIN@"

usage() {
  cat <<EOF
ccode - claude-code with per-profile config directories

usage: ccode [options] [claude options and args...]

options:
  --profile <name>  run under profile <name>
  -l, --list        list available profiles
  -h, --help        show this help and exit

Without --profile, the default profile is used; change it with
CCODE_PROFILE=<name>. Profiles live in $PROFILES_DIR and are created on
first use. All remaining arguments are passed to claude unchanged (use
'--' if a claude argument could be mistaken for a ccode option).
EOF
}

die() {
  printf 'ccode: %s\n' "$*" >&2
  exit 2
}

list_profiles() {
  if [ ! -d "$PROFILES_DIR" ]; then
    printf 'no profiles yet (created on first use in %s)\n' "$PROFILES_DIR"
    return 0
  fi
  default="${CCODE_PROFILE:-$DEFAULT_PROFILE}"
  found=0
  for dir in "$PROFILES_DIR"/*/; do
    [ -d "$dir" ] || continue
    name="${dir%/}"
    name="${name##*/}"
    if [ "$name" = "$default" ]; then
      printf '%s (default)\n' "$name"
    else
      printf '%s\n' "$name"
    fi
    found=1
  done
  if [ "$found" = 0 ]; then
    printf 'no profiles yet (created on first use in %s)\n' "$PROFILES_DIR"
  fi
}

profile=""
profile_set=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -l | --list)
      list_profiles
      exit 0
      ;;
    --profile)
      if [ $# -lt 2 ]; then
        die "--profile requires a value"
      fi
      profile_set=1
      profile="$2"
      shift 2
      ;;
    --profile=*)
      profile_set=1
      profile="${1#--profile=}"
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [ "$profile_set" = 0 ]; then
  profile="${CCODE_PROFILE:-$DEFAULT_PROFILE}"
fi
if [ -z "$profile" ]; then
  die "no profile configured; use --profile <name> or CCODE_PROFILE=<name>"
fi
case "$profile" in
  *[!A-Za-z0-9._-]*)
    die "invalid profile name '$profile' (allowed: letters, digits, '.', '_' and '-')"
    ;;
esac

config_dir="$PROFILES_DIR/$profile"
if ! mkdir -p "$config_dir" 2>/dev/null; then
  die "cannot create $config_dir"
fi

CLAUDE_CONFIG_DIR="$config_dir"
export CLAUDE_CONFIG_DIR
exec "$CLAUDE_BIN" "$@"
