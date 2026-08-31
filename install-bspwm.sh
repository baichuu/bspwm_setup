#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
eww_build_dir=''

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
  [[ -n ${VERSION_CODENAME:-} ]] || die "Cannot detect the Ubuntu release codename."
}

backup_file() {
  local path=$1
  if [[ -e $path ]] && ! cmp -s "$path" "$path.bspwm-setup" 2>/dev/null; then
    cp -a -- "$path" "$path.bak.$(date +%Y%m%d-%H%M%S)"
    warn "Backed up existing file: $path"
  fi
}

backup_directory() {
  local path=$1
  local source=$2
  if [[ -d $path ]] && ! diff -qr --exclude='.bspwm-setup' "$source" "$path" >/dev/null; then
    cp -a -- "$path" "$path.bak.$(date +%Y%m%d-%H%M%S)"
    warn "Backed up existing directory: $path"
  fi
}

cleanup_eww_build() {
  [[ -n $eww_build_dir ]] || return 0
  [[ $eww_build_dir == /tmp/bspwm-eww.* ]] || return 0
  rm -rf -- "$eww_build_dir"
  eww_build_dir=''
}

trap cleanup_eww_build EXIT

install_eww() {
  if command -v eww >/dev/null 2>&1; then
    log "Using the existing Eww installation: $(command -v eww)"
    return
  fi

  local cargo_home
  local rustup_home
  local -a new_packages
  eww_build_dir=$(mktemp -d /tmp/bspwm-eww.XXXXXX)
  cargo_home="$eww_build_dir/cargo"
  rustup_home="$eww_build_dir/rustup"

  log "Building the X11-only Eww binary in a temporary directory..."
  dpkg-query -W -f='${binary:Package}\n' | sort -u >"$eww_build_dir/packages.before"
  apt-get install -y --no-install-recommends \
    build-essential \
    git \
    pkg-config \
    libgtk-3-dev \
    libdbusmenu-gtk3-dev \
    libx11-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxi-dev \
    libxext-dev \
    libxcb1-dev \
    libxcb-randr0-dev

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
    CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" \
      sh -s -- -y --profile minimal --default-toolchain stable --no-modify-path
  git clone --depth 1 --branch v0.6.0 https://github.com/elkowar/eww.git "$eww_build_dir/source"
  CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" \
    "$cargo_home/bin/cargo" build \
    --manifest-path "$eww_build_dir/source/Cargo.toml" \
    --release \
    --locked \
    --no-default-features \
    --features x11
  strip "$eww_build_dir/source/target/release/eww"
  install -m 0755 "$eww_build_dir/source/target/release/eww" /usr/local/bin/eww

  dpkg-query -W -f='${binary:Package}\n' | sort -u >"$eww_build_dir/packages.after"
  mapfile -t new_packages < <(comm -13 "$eww_build_dir/packages.before" "$eww_build_dir/packages.after")
  if ((${#new_packages[@]})); then
    apt-get purge -y "${new_packages[@]}"
  fi

  /usr/local/bin/eww --version
  cleanup_eww_build
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

for required_config in \
  config/alacritty/alacritty.toml \
  config/dunst/dunstrc \
  config/dunst/notification.png \
  config/eww/eww.scss \
  config/eww/eww.yuck \
  config/eww/scripts/cpu \
  config/eww/scripts/brightness-control \
  config/eww/scripts/memory \
  config/eww/scripts/powermenu \
  config/eww/scripts/updates \
  config/eww/scripts/volume-status \
  config/fonts/IosevkaNerdFont-Regular.ttf \
  config/gtk-2.0/gtkrc \
  config/gtk-3.0/settings.ini \
  config/picom/picom.conf \
  config/picom/picom-legacy.conf \
  config/wallpaper/bspwm-wallpaper.png \
  config/x11/Xresources \
  config/zathura/zathurarc \
  config/zsh/.zshrc \
  config/gtk-theme/siduck-onedark/index.theme; do
  [[ -r "$SCRIPT_DIR/$required_config" ]] || die "Missing configuration file: $required_config"
done

packages=(
  xserver-xorg
  xinit
  xauth
  x11-xserver-utils
  bspwm
  sxhkd
  alacritty
  rofi
  chromium
  picom
  dunst
  feh
  zathura
  zathura-pdf-poppler
  zsh
  pipewire
  pipewire-pulse
  wireplumber
  papirus-icon-theme
  bibata-cursor-theme
  gtk2-engines-murrine
  gtk2-engines-pixbuf
  libdbusmenu-gtk3-4
  fontconfig
  libxkbcommon0
  libxkbcommon-x11-0
  xkb-data
  fonts-dejavu-core
)

log "Updating package indexes..."
export DEBIAN_FRONTEND=noninteractive
apt-get update

log "Enabling the XtraDeb repository for a non-Snap Chromium package..."
apt-get install -y --no-install-recommends ca-certificates curl
install -d -m 0755 /etc/apt/keyrings
curl -fsSL \
  'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x5301FA4FD93244FBC6F6149982BB6851C64F6880' \
  -o /etc/apt/keyrings/xtradeb.asc
install -m 0644 /dev/stdin /etc/apt/sources.list.d/xtradeb-apps.sources <<EOF
Types: deb
URIs: https://ppa.launchpadcontent.net/xtradeb/apps/ubuntu
Suites: $VERSION_CODENAME
Components: main
Signed-By: /etc/apt/keyrings/xtradeb.asc
EOF
apt-get update

log "Installing bspwm and desktop applications..."
apt-get install -y --no-install-recommends "${packages[@]}"
install_eww

picom_config_source="$SCRIPT_DIR/config/picom/picom.conf"
picom_major=$(picom --version | sed -nE 's/^[^0-9]*([0-9]+).*/\1/p' | head -n 1)
if [[ ! $picom_major =~ ^[0-9]+$ ]] || ((picom_major < 12)); then
  warn "Picom 12 or newer is required for scripted animations; using basic fading instead."
  picom_config_source="$SCRIPT_DIR/config/picom/picom-legacy.conf"
fi

config_dir="$target_home/.config"
bspwm_dir="$config_dir/bspwm"
sxhkd_dir="$config_dir/sxhkd"
alacritty_dir="$config_dir/alacritty"
dunst_dir="$config_dir/dunst"
dunst_icon_dir="$dunst_dir/icons"
picom_dir="$config_dir/picom"
eww_dir="$config_dir/eww"
zathura_dir="$config_dir/zathura"
gtk3_dir="$config_dir/gtk-3.0"
wallpaper_dir="$target_home/.local/share/backgrounds"
gtk_theme_dir="$target_home/.themes/siduck-onedark"
font_dir="$target_home/.local/share/fonts/Iosevka"
mkdir -p \
  "$bspwm_dir" \
  "$sxhkd_dir" \
  "$alacritty_dir" \
  "$dunst_dir" \
  "$dunst_icon_dir" \
  "$picom_dir" \
  "$zathura_dir" \
  "$gtk3_dir" \
  "$wallpaper_dir" \
  "$font_dir"

backup_file "$bspwm_dir/bspwmrc"
backup_file "$sxhkd_dir/sxhkdrc"
backup_file "$alacritty_dir/alacritty.toml"
backup_file "$dunst_dir/dunstrc"
backup_file "$dunst_icon_dir/notification.png"
backup_file "$picom_dir/picom.conf"
backup_file "$zathura_dir/zathurarc"
backup_file "$gtk3_dir/settings.ini"
backup_file "$target_home/.gtkrc-2.0"
backup_file "$target_home/.zshrc"
backup_file "$target_home/.Xresources"
backup_file "$wallpaper_dir/bspwm-wallpaper.png"
backup_file "$font_dir/IosevkaNerdFont-Regular.ttf"
backup_file "$target_home/.xinitrc"
backup_directory "$gtk_theme_dir" "$SCRIPT_DIR/config/gtk-theme/siduck-onedark"
backup_directory "$eww_dir" "$SCRIPT_DIR/config/eww"
mkdir -p "$gtk_theme_dir"
mkdir -p "$eww_dir"

log "Writing the starter configuration for $target_user..."
install -m 0755 /dev/stdin "$bspwm_dir/bspwmrc" <<'EOF'
#!/bin/sh

pgrep -u "$(id -u)" -x sxhkd >/dev/null || sxhkd &
pgrep -u "$(id -u)" -x picom >/dev/null || picom &
pgrep -u "$(id -u)" -x dunst >/dev/null || dunst &
systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 || true
xsetroot -solid '#171717'
xrdb -merge "$HOME/.Xresources"
xsetroot -cursor_name left_ptr
feh --no-fehbg --bg-fill "$HOME/.local/share/backgrounds/bspwm-wallpaper.png" &

bspc monitor -d 1 2 3
bspc config border_width 2
bspc config window_gap 8
bspc config split_ratio 0.52
bspc config borderless_monocle true
bspc config gapless_monocle true
bspc config normal_border_color '#242424'
bspc config active_border_color '#888888'
bspc config focused_border_color '#76bef9'
bspc config presel_feedback_color '#c993ef'

eww daemon >/dev/null 2>&1
eww open bar-window >/dev/null 2>&1 || true
EOF

install -m 0644 /dev/stdin "$sxhkd_dir/sxhkdrc" <<'EOF'
# Applications
super + Return
    alacritty

super + space
    rofi -show drun

super + b
    chromium --ozone-platform=x11

# Window manager
super + shift + r
    eww reload >/dev/null 2>&1; pkill -USR1 -u "$(id -u)" -x sxhkd; bspc wm -r

super + q
    bspc node -c

super + {h,j,k,l}
    bspc node -f {west,south,north,east}

super + shift + {h,j,k,l}
    bspc node -s {west,south,north,east}

super + {1-3}
    bspc desktop -f '^{1-3}'

super + shift + {1-3}
    bspc node -d '^{1-3}'

# PipeWire audio and backlight
XF86AudioRaiseVolume
    wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+

XF86AudioLowerVolume
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-

XF86AudioMute
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

XF86MonBrightnessUp
    ~/.config/eww/scripts/brightness-control up

XF86MonBrightnessDown
    ~/.config/eww/scripts/brightness-control down
EOF

install -m 0644 \
  "$SCRIPT_DIR/config/alacritty/alacritty.toml" \
  "$alacritty_dir/alacritty.toml"
install -m 0644 "$SCRIPT_DIR/config/dunst/dunstrc" "$dunst_dir/dunstrc"
install -m 0644 \
  "$SCRIPT_DIR/config/dunst/notification.png" \
  "$dunst_icon_dir/notification.png"
install -m 0644 "$picom_config_source" "$picom_dir/picom.conf"
install -m 0644 "$SCRIPT_DIR/config/zathura/zathurarc" "$zathura_dir/zathurarc"
install -m 0644 "$SCRIPT_DIR/config/gtk-3.0/settings.ini" "$gtk3_dir/settings.ini"
install -m 0644 "$SCRIPT_DIR/config/gtk-2.0/gtkrc" "$target_home/.gtkrc-2.0"
install -m 0644 "$SCRIPT_DIR/config/zsh/.zshrc" "$target_home/.zshrc"
install -m 0644 "$SCRIPT_DIR/config/x11/Xresources" "$target_home/.Xresources"
install -m 0644 \
  "$SCRIPT_DIR/config/wallpaper/bspwm-wallpaper.png" \
  "$wallpaper_dir/bspwm-wallpaper.png"
cp -a -- "$SCRIPT_DIR/config/gtk-theme/siduck-onedark/." "$gtk_theme_dir/"
touch "$gtk_theme_dir/.bspwm-setup"
cp -a -- "$SCRIPT_DIR/config/eww/." "$eww_dir/"
touch "$eww_dir/.bspwm-setup"
install -m 0644 \
  "$SCRIPT_DIR/config/fonts/IosevkaNerdFont-Regular.ttf" \
  "$font_dir/IosevkaNerdFont-Regular.ttf"

install -m 0755 /dev/stdin "$target_home/.xinitrc" <<'EOF'
#!/bin/sh

export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export WINIT_UNIX_BACKEND=x11
export GTK_THEME=siduck-onedark
export XCURSOR_THEME=Bibata-Modern-Ice
export XCURSOR_SIZE=24

exec bspwm
EOF

# Save pristine copies so a later run can distinguish our files from user edits.
cp -a -- "$bspwm_dir/bspwmrc" "$bspwm_dir/bspwmrc.bspwm-setup"
cp -a -- "$sxhkd_dir/sxhkdrc" "$sxhkd_dir/sxhkdrc.bspwm-setup"
cp -a -- "$alacritty_dir/alacritty.toml" "$alacritty_dir/alacritty.toml.bspwm-setup"
cp -a -- "$dunst_dir/dunstrc" "$dunst_dir/dunstrc.bspwm-setup"
cp -a -- \
  "$dunst_icon_dir/notification.png" \
  "$dunst_icon_dir/notification.png.bspwm-setup"
cp -a -- "$picom_dir/picom.conf" "$picom_dir/picom.conf.bspwm-setup"
cp -a -- "$zathura_dir/zathurarc" "$zathura_dir/zathurarc.bspwm-setup"
cp -a -- "$gtk3_dir/settings.ini" "$gtk3_dir/settings.ini.bspwm-setup"
cp -a -- "$target_home/.gtkrc-2.0" "$target_home/.gtkrc-2.0.bspwm-setup"
cp -a -- "$target_home/.zshrc" "$target_home/.zshrc.bspwm-setup"
cp -a -- "$target_home/.Xresources" "$target_home/.Xresources.bspwm-setup"
cp -a -- \
  "$wallpaper_dir/bspwm-wallpaper.png" \
  "$wallpaper_dir/bspwm-wallpaper.png.bspwm-setup"
cp -a -- \
  "$font_dir/IosevkaNerdFont-Regular.ttf" \
  "$font_dir/IosevkaNerdFont-Regular.ttf.bspwm-setup"
cp -a -- "$target_home/.xinitrc" "$target_home/.xinitrc.bspwm-setup"

chown -R "$target_user:$target_group" \
  "$bspwm_dir" \
  "$sxhkd_dir" \
  "$alacritty_dir" \
  "$dunst_dir" \
  "$picom_dir" \
  "$eww_dir" \
  "$zathura_dir" \
  "$gtk3_dir" \
  "$wallpaper_dir" \
  "$gtk_theme_dir" \
  "$font_dir"
chown "$target_user:$target_group" \
  "$target_home/.gtkrc-2.0" \
  "$target_home/.gtkrc-2.0.bspwm-setup" \
  "$target_home/.zshrc" \
  "$target_home/.zshrc.bspwm-setup" \
  "$target_home/.Xresources" \
  "$target_home/.Xresources.bspwm-setup" \
  "$target_home/.xinitrc" \
  "$target_home/.xinitrc.bspwm-setup"

runuser -u "$target_user" -- fc-cache -f "$font_dir"

zsh_path=$(command -v zsh)
if [[ $(getent passwd "$target_user" | cut -d: -f7) != "$zsh_path" ]]; then
  usermod --shell "$zsh_path" "$target_user"
  log "Set Zsh as the login shell for $target_user."
fi

log "Installation complete."
log "Log in on a TTY and run: startx"
