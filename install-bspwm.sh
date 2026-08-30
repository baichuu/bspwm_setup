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

Install a bspwm desktop and common desktop utilities on Ubuntu Server minimal.

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
  alacritty
  rofi
  chromium-browser
  picom
  dunst
  polybar
  libxkbcommon0
  libxkbcommon-x11-0
  xkb-data
  fonts-dejavu-core
)

log "Updating package indexes..."
export DEBIAN_FRONTEND=noninteractive
apt-get update

log "Installing bspwm and desktop applications..."
apt-get install -y --no-install-recommends "${packages[@]}"

config_dir="$target_home/.config"
bspwm_dir="$config_dir/bspwm"
sxhkd_dir="$config_dir/sxhkd"
polybar_dir="$config_dir/polybar"
mkdir -p "$bspwm_dir" "$sxhkd_dir" "$polybar_dir"

backup_file "$bspwm_dir/bspwmrc"
backup_file "$sxhkd_dir/sxhkdrc"
backup_file "$polybar_dir/config.ini"
backup_file "$target_home/.xinitrc"

log "Writing the starter configuration for $target_user..."
install -m 0755 /dev/stdin "$bspwm_dir/bspwmrc" <<'EOF'
#!/bin/sh

pgrep -u "$(id -u)" -x sxhkd >/dev/null || sxhkd &
pgrep -u "$(id -u)" -x picom >/dev/null || picom &
pgrep -u "$(id -u)" -x dunst >/dev/null || dunst &
xsetroot -solid '#1e1e2e'

bspc monitor -d 1 2 3 4 5 6 7 8 9 10
bspc config border_width 2
bspc config window_gap 8
bspc config split_ratio 0.52
bspc config borderless_monocle true
bspc config gapless_monocle true

pgrep -u "$(id -u)" -x polybar >/dev/null || polybar main &
EOF

install -m 0644 /dev/stdin "$sxhkd_dir/sxhkdrc" <<'EOF'
# Applications
super + Return
    alacritty

super + space
    rofi -show drun

super + b
    chromium-browser

# Window manager
super + shift + r
    pkill -USR1 -u "$(id -u)" -x sxhkd; bspc wm -r

super + q
    bspc node -c

super + {h,j,k,l}
    bspc node -f {west,south,north,east}

super + shift + {h,j,k,l}
    bspc node -s {west,south,north,east}

super + {1-9,0}
    bspc desktop -f '^{1-9,10}'

super + shift + {1-9,0}
    bspc node -d '^{1-9,10}'
EOF

install -m 0644 /dev/stdin "$polybar_dir/config.ini" <<'EOF'
[colors]
background = #1e1e2e
foreground = #cdd6f4
accent = #89b4fa
muted = #6c7086
urgent = #f38ba8

[bar/main]
width = 100%
height = 28
background = ${colors.background}
foreground = ${colors.foreground}
line-size = 2
padding-left = 1
padding-right = 1
module-margin = 1
font-0 = monospace:size=10;2
modules-left = bspwm
modules-center = xwindow
modules-right = cpu memory date
wm-restack = bspwm
enable-ipc = true

[module/bspwm]
type = internal/bspwm
pin-workspaces = true
label-focused = %name%
label-focused-foreground = ${colors.accent}
label-focused-underline = ${colors.accent}
label-focused-padding = 1
label-occupied = %name%
label-occupied-padding = 1
label-empty = %name%
label-empty-foreground = ${colors.muted}
label-empty-padding = 1
label-urgent = %name%
label-urgent-foreground = ${colors.urgent}
label-urgent-padding = 1

[module/xwindow]
type = internal/xwindow
label = %title:0:60:...%

[module/cpu]
type = internal/cpu
interval = 2
label = CPU %percentage%%

[module/memory]
type = internal/memory
interval = 2
label = RAM %percentage_used%%

[module/date]
type = internal/date
interval = 1
date = %a %d/%m %H:%M
EOF

install -m 0755 /dev/stdin "$target_home/.xinitrc" <<'EOF'
#!/bin/sh
exec bspwm
EOF

# Save pristine copies so a later run can distinguish our files from user edits.
cp -a -- "$bspwm_dir/bspwmrc" "$bspwm_dir/bspwmrc.bspwm-setup"
cp -a -- "$sxhkd_dir/sxhkdrc" "$sxhkd_dir/sxhkdrc.bspwm-setup"
cp -a -- "$polybar_dir/config.ini" "$polybar_dir/config.ini.bspwm-setup"
cp -a -- "$target_home/.xinitrc" "$target_home/.xinitrc.bspwm-setup"

chown -R "$target_user:$target_group" "$bspwm_dir" "$sxhkd_dir" "$polybar_dir"
chown "$target_user:$target_group" \
  "$target_home/.xinitrc" "$target_home/.xinitrc.bspwm-setup"

log "Installation complete."
log "Log in on a TTY and run: startx"
