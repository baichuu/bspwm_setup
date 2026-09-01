#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '\033[1;32m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"
}

warn() {
  printf '\033[1;33m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2
}

die() {
  printf '\033[1;31m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: sudo ./$SCRIPT_NAME [--user USER]

Recreate only the repository-backed desktop configuration links. This does not
install packages, build software, configure swap, or install Vivado/OpenEye.
EOF
}

target_user="${SUDO_USER:-}"
while (($#)); do
  case $1 in
  --user)
    (($# >= 2)) || die '--user requires a user name.'
    target_user=$2
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "Unknown option: $1" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "Run with sudo: sudo ./$SCRIPT_NAME"
[[ -n $target_user && $target_user != root ]] || die 'Specify a regular user with --user USER.'
getent passwd "$target_user" >/dev/null || die "User does not exist: $target_user"
target_home=$(getent passwd "$target_user" | cut -d: -f6)
target_group=$(id -gn "$target_user")
[[ -d $target_home ]] || die "Home directory does not exist: $target_home"

# shellcheck source=lib/config-links.sh
source "$SCRIPT_DIR/lib/config-links.sh"

log "Applying repository-backed configuration links for $target_user..."
install_desktop_config_links
if command -v fc-cache >/dev/null 2>&1; then
  runuser -u "$target_user" -- fc-cache -f \
    "$target_home/.local/share/fonts/Iosevka" \
    "$target_home/.local/share/fonts/Icons" >/dev/null
fi

log 'Configuration links are ready.'
log 'Use Super+Shift+R inside bspwm to reload the bar, sxhkd, and bspwm.'
log 'Restart Xorg after changing the touchpad InputClass configuration.'
