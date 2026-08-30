#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"

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

Install a basic bspwm desktop on Ubuntu Server minimal.

Options:
  --user USER    Configure bspwm for USER (default: the user who called sudo)
  -h, --help     Show this help
EOF
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "Run this script with sudo: sudo ./$SCRIPT_NAME"
  fi
}

check_ubuntu() {
  [[ -r /etc/os-release ]] || die "Cannot detect the operating system."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == ubuntu ]] || die "This script supports Ubuntu only (detected: ${ID:-unknown})."
}

backup_file() {
  local path=$1
  if [[ -e $path ]] && ! cmp -s "$path" "$path.bspwm-setup" 2>/dev/null; then
    cp -a -- "$path" "$path.bak.$(date +%Y%m%d-%H%M%S)"
    warn "Backed up existing file: $path"
  fi
}

target_user="${SUDO_USER:-}"

while (($#)); do
  case $1 in
  --user)
    (($# >= 2)) || die "--user requires a user name."
    target_user=$2
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "Unknown option: $1"
    ;;
  esac
done

require_root
check_ubuntu

[[ -n $target_user && $target_user != root ]] || die "Specify a normal user with --user USER."
getent passwd "$target_user" >/dev/null || die "User '$target_user' does not exist."

target_home=$(getent passwd "$target_user" | cut -d: -f6)
target_group=$(id -gn "$target_user")
[[ -d $target_home ]] || die "Home directory does not exist: $target_home"

packages=(
  xorg
  xinit
  bspwm
  sxhkd
  xterm
)

log "Updating package indexes..."
export DEBIAN_FRONTEND=noninteractive
apt-get update

log "Installing bspwm and the basic desktop packages..."
apt-get install -y --no-install-recommends "${packages[@]}"

config_dir="$target_home/.config"
bspwm_dir="$config_dir/bspwm"
sxhkd_dir="$config_dir/sxhkd"
mkdir -p "$bspwm_dir" "$sxhkd_dir"

backup_file "$bspwm_dir/bspwmrc"
backup_file "$sxhkd_dir/sxhkdrc"
backup_file "$target_home/.xinitrc"

log "Writing the starter configuration for $target_user..."
install -m 0755 /dev/stdin "$bspwm_dir/bspwmrc" <<'EOF'
#!/bin/sh

sxhkd &
xsetroot -solid '#1e1e2e'
EOF

install -m 0644 /dev/stdin "$sxhkd_dir/sxhkdrc" <<'EOF'
# Release the left Windows/Super key to open a terminal.
@Super_L
    xterm
EOF

install -m 0755 /dev/stdin "$target_home/.xinitrc" <<'EOF'
#!/bin/sh
exec bspwm
EOF

# Save pristine copies so a later run can distinguish our files from user edits.
cp -a -- "$bspwm_dir/bspwmrc" "$bspwm_dir/bspwmrc.bspwm-setup"
cp -a -- "$sxhkd_dir/sxhkdrc" "$sxhkd_dir/sxhkdrc.bspwm-setup"
cp -a -- "$target_home/.xinitrc" "$target_home/.xinitrc.bspwm-setup"

chown -R "$target_user:$target_group" "$bspwm_dir" "$sxhkd_dir"
chown "$target_user:$target_group" \
  "$target_home/.xinitrc" "$target_home/.xinitrc.bspwm-setup"

log "Installation complete."
log "Log in on a TTY and run: startx"
