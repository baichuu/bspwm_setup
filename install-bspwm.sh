#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
eww_build_dir=''
neovim_tmp_dir=''
picom_build_dir=''

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

cleanup_build_dirs() {
  if [[ -n $eww_build_dir && $eww_build_dir == /tmp/bspwm-eww.* ]]; then
    rm -rf -- "$eww_build_dir"
    eww_build_dir=''
  fi
  if [[ -n $neovim_tmp_dir && $neovim_tmp_dir == /tmp/bspwm-neovim.* ]]; then
    rm -rf -- "$neovim_tmp_dir"
    neovim_tmp_dir=''
  fi
  if [[ -n $picom_build_dir && $picom_build_dir == /tmp/bspwm-picom.* ]]; then
    rm -rf -- "$picom_build_dir"
    picom_build_dir=''
  fi
}

trap cleanup_build_dirs EXIT

install_eww() {
  if command -v eww >/dev/null 2>&1; then
    log "Using the existing Eww installation: $(command -v eww)"
    return
  fi

  local cargo_home
  local rustup_home
  eww_build_dir=$(mktemp -d /tmp/bspwm-eww.XXXXXX)
  cargo_home="$eww_build_dir/cargo"
  rustup_home="$eww_build_dir/rustup"

  log "Building the X11-only Eww binary in a temporary directory..."
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
      sh -s -- -y --profile minimal --default-toolchain 1.77.2 --no-modify-path
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

  /usr/local/bin/eww --version
  rm -rf -- "$eww_build_dir"
  eww_build_dir=''
}

install_neovim() {
  local version='0.11.7'
  local asset_arch
  local archive
  local archive_root
  local expected_sha256
  local install_dir="/opt/nvim-$version"

  if command -v nvim >/dev/null 2>&1 &&
    [[ $(nvim --version | sed -n '1p') == "NVIM v$version" ]]; then
    log "Using the existing Neovim $version installation: $(command -v nvim)"
    return
  fi

  if [[ $(dpkg-query -W -f='${db:Status-Status}' neovim 2>/dev/null || true) == installed ]]; then
    log "Removing the older Ubuntu Neovim package before installing v$version..."
    apt-get purge -y neovim neovim-runtime
  fi

  case $(dpkg --print-architecture) in
  amd64)
    asset_arch='x86_64'
    expected_sha256='38a7c6317f94503841096c00e8fde05ef04b9472fc9d7d62b6e033cecd6f7991'
    ;;
  arm64)
    asset_arch='arm64'
    expected_sha256='99bb3c53604e83ce18fc0b459e34cf1a5e212f4e5fbe2eb136b3c18092ae9905'
    ;;
  *) die "Neovim $version has no supported release tarball for $(dpkg --print-architecture)." ;;
  esac

  archive="nvim-linux-$asset_arch.tar.gz"
  archive_root="nvim-linux-$asset_arch"
  neovim_tmp_dir=$(mktemp -d /tmp/bspwm-neovim.XXXXXX)

  log "Installing Neovim $version from the official Linux release..."
  curl -fL --retry 3 \
    "https://github.com/neovim/neovim/releases/download/v$version/$archive" \
    -o "$neovim_tmp_dir/$archive"
  printf '%s  %s\n' "$expected_sha256" "$neovim_tmp_dir/$archive" |
    sha256sum --check --status - || die "Neovim release checksum verification failed."
  tar -xzf "$neovim_tmp_dir/$archive" -C "$neovim_tmp_dir"
  [[ -x "$neovim_tmp_dir/$archive_root/bin/nvim" ]] ||
    die "The Neovim release archive did not contain the expected binary."

  rm -rf -- "$install_dir.new"
  cp -a -- "$neovim_tmp_dir/$archive_root" "$install_dir.new"
  rm -rf -- "$install_dir"
  mv -- "$install_dir.new" "$install_dir"
  ln -sfn -- "$install_dir/bin/nvim" /usr/local/bin/nvim

  [[ $(/usr/local/bin/nvim --version | sed -n '1p') == "NVIM v$version" ]] ||
    die "Neovim $version verification failed."
  rm -rf -- "$neovim_tmp_dir"
  neovim_tmp_dir=''
}

install_picom() {
  local version='13'

  if command -v picom >/dev/null 2>&1 &&
    [[ $(picom --version 2>/dev/null) == *"v$version"* ]]; then
    log "Using the existing Picom v$version installation: $(command -v picom)"
    return
  fi

  if [[ $(dpkg-query -W -f='${db:Status-Status}' picom 2>/dev/null || true) == installed ]]; then
    log "Removing the older Ubuntu Picom package before building v$version..."
    apt-get purge -y picom
  fi

  picom_build_dir=$(mktemp -d /tmp/bspwm-picom.XXXXXX)
  log "Building Picom v$version with the lightweight XRender feature set..."
  apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    meson \
    ninja-build \
    pkg-config \
    libconfig-dev \
    libev-dev \
    libpixman-1-dev \
    libx11-xcb-dev \
    libxcb1-dev \
    libxcb-composite0-dev \
    libxcb-damage0-dev \
    libxcb-glx0-dev \
    libxcb-image0-dev \
    libxcb-present-dev \
    libxcb-randr0-dev \
    libxcb-render0-dev \
    libxcb-render-util0-dev \
    libxcb-shape0-dev \
    libxcb-util-dev \
    libxcb-xfixes0-dev \
    uthash-dev

  git clone --depth 1 --branch "v$version" \
    https://github.com/yshui/picom.git "$picom_build_dir/source"
  git -C "$picom_build_dir/source" submodule update --init --recursive
  meson setup "$picom_build_dir/source/build" "$picom_build_dir/source" \
    --buildtype=release \
    --prefix=/usr/local \
    -Ddbus=false \
    -Dopengl=false \
    -Dregex=false \
    -Dwith_docs=false \
    -Dcompton=false
  ninja -C "$picom_build_dir/source/build"
  strip "$picom_build_dir/source/build/src/picom"
  install -m 0755 "$picom_build_dir/source/build/src/picom" /usr/local/bin/picom

  [[ $(/usr/local/bin/picom --version 2>/dev/null) == *"v$version"* ]] ||
    die "Picom v$version verification failed."
  rm -rf -- "$picom_build_dir"
  picom_build_dir=''
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
  config/bspwm/bspwmrc \
  config/dunst/dunstrc \
  config/dunst/notification.png \
  config/eww/eww.scss \
  config/eww/eww.yuck \
  config/eww/scripts/cpu \
  config/eww/scripts/brightness-control \
  config/eww/scripts/memory \
  config/eww/scripts/powermenu \
  config/eww/scripts/screenshot \
  config/eww/scripts/updates \
  config/eww/scripts/volume-status \
  config/fonts/feather.ttf \
  config/fonts/IosevkaNerdFont-Regular.ttf \
  config/gtk-2.0/gtkrc \
  config/gtk-3.0/settings.ini \
  config/picom/picom.conf \
  config/rofi/launcher.rasi \
  config/rofi/powermenu.rasi \
  config/rofi/screenshot.rasi \
  config/sxhkd/sxhkdrc \
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
  chromium-sandbox
  dunst
  feh
  flameshot
  zathura
  zathura-pdf-poppler
  zsh
  pipewire
  pipewire-pulse
  wireplumber
  papirus-icon-theme
  gtk-update-icon-cache
  bibata-cursor-theme
  gtk2-engines-murrine
  gtk2-engines-pixbuf
  libdbusmenu-gtk3-4
  libxcb-composite0
  libxcb-damage0
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

# Install Picom's runtime libraries explicitly. Ubuntu may use t64 package names.
if apt-cache show libconfig9t64 2>/dev/null | grep -q '^Package: libconfig9t64$'; then
  packages+=(libconfig9t64)
elif apt-cache show libconfig9 2>/dev/null | grep -q '^Package: libconfig9$'; then
  packages+=(libconfig9)
else
  die "Cannot find an Ubuntu libconfig runtime package required by Picom."
fi
if apt-cache show libev4t64 2>/dev/null | grep -q '^Package: libev4t64$'; then
  packages+=(libev4t64)
elif apt-cache show libev4 2>/dev/null | grep -q '^Package: libev4$'; then
  packages+=(libev4)
else
  die "Cannot find an Ubuntu libev runtime package required by Picom."
fi

log "Installing bspwm and desktop applications..."
apt-get install -y --no-install-recommends "${packages[@]}"
gtk-update-icon-cache -f /usr/share/icons/Papirus-Dark >/dev/null 2>&1 || true
install_neovim
install_picom
install_eww

picom_config_source="$SCRIPT_DIR/config/picom/picom.conf"

config_dir="$target_home/.config"
bspwm_dir="$config_dir/bspwm"
sxhkd_dir="$config_dir/sxhkd"
alacritty_dir="$config_dir/alacritty"
dunst_dir="$config_dir/dunst"
dunst_icon_dir="$dunst_dir/icons"
picom_dir="$config_dir/picom"
rofi_dir="$config_dir/rofi"
eww_dir="$config_dir/eww"
zathura_dir="$config_dir/zathura"
gtk3_dir="$config_dir/gtk-3.0"
wallpaper_dir="$target_home/.local/share/backgrounds"
gtk_theme_dir="$target_home/.themes/siduck-onedark"
font_dir="$target_home/.local/share/fonts/Iosevka"
icon_font_dir="$target_home/.local/share/fonts/Icons"
# These parent directories may not exist on Ubuntu Server minimal. Create them
# with the target user's ownership; otherwise ~/.config itself remains owned by
# root and applications such as Chromium cannot create their state directories.
install -d -m 0755 -o "$target_user" -g "$target_group" \
  "$config_dir" \
  "$target_home/.local" \
  "$target_home/.local/share" \
  "$target_home/.local/share/fonts" \
  "$target_home/.themes"
mkdir -p \
  "$bspwm_dir" \
  "$sxhkd_dir" \
  "$alacritty_dir" \
  "$dunst_dir" \
  "$dunst_icon_dir" \
  "$picom_dir" \
  "$rofi_dir" \
  "$zathura_dir" \
  "$gtk3_dir" \
  "$wallpaper_dir" \
  "$font_dir" \
  "$icon_font_dir"

backup_file "$bspwm_dir/bspwmrc"
backup_file "$sxhkd_dir/sxhkdrc"
backup_file "$alacritty_dir/alacritty.toml"
backup_file "$dunst_dir/dunstrc"
backup_file "$dunst_icon_dir/notification.png"
backup_file "$picom_dir/picom.conf"
backup_file "$rofi_dir/launcher.rasi"
backup_file "$rofi_dir/powermenu.rasi"
backup_file "$rofi_dir/screenshot.rasi"
backup_file "$zathura_dir/zathurarc"
backup_file "$gtk3_dir/settings.ini"
backup_file "$target_home/.gtkrc-2.0"
backup_file "$target_home/.zshrc"
backup_file "$target_home/.Xresources"
backup_file "$wallpaper_dir/bspwm-wallpaper.png"
backup_file "$font_dir/IosevkaNerdFont-Regular.ttf"
backup_file "$icon_font_dir/feather.ttf"
backup_file "$target_home/.xinitrc"
backup_directory "$gtk_theme_dir" "$SCRIPT_DIR/config/gtk-theme/siduck-onedark"
backup_directory "$eww_dir" "$SCRIPT_DIR/config/eww"
mkdir -p "$gtk_theme_dir"
mkdir -p "$eww_dir"

log "Writing the starter configuration for $target_user..."
install -m 0755 "$SCRIPT_DIR/config/bspwm/bspwmrc" "$bspwm_dir/bspwmrc"
install -m 0644 "$SCRIPT_DIR/config/sxhkd/sxhkdrc" "$sxhkd_dir/sxhkdrc"
install -m 0644 \
  "$SCRIPT_DIR/config/alacritty/alacritty.toml" \
  "$alacritty_dir/alacritty.toml"
install -m 0644 "$SCRIPT_DIR/config/dunst/dunstrc" "$dunst_dir/dunstrc"
install -m 0644 \
  "$SCRIPT_DIR/config/dunst/notification.png" \
  "$dunst_icon_dir/notification.png"
install -m 0644 "$picom_config_source" "$picom_dir/picom.conf"
install -m 0644 "$SCRIPT_DIR/config/rofi/launcher.rasi" "$rofi_dir/launcher.rasi"
install -m 0644 "$SCRIPT_DIR/config/rofi/powermenu.rasi" "$rofi_dir/powermenu.rasi"
install -m 0644 "$SCRIPT_DIR/config/rofi/screenshot.rasi" "$rofi_dir/screenshot.rasi"
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
install -m 0644 \
  "$SCRIPT_DIR/config/fonts/feather.ttf" \
  "$icon_font_dir/feather.ttf"

install -m 0755 /dev/stdin "$target_home/.xinitrc" <<'EOF'
#!/bin/sh

export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export WINIT_UNIX_BACKEND=x11
export SHELL=/usr/bin/zsh
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
cp -a -- "$rofi_dir/launcher.rasi" "$rofi_dir/launcher.rasi.bspwm-setup"
cp -a -- "$rofi_dir/powermenu.rasi" "$rofi_dir/powermenu.rasi.bspwm-setup"
cp -a -- "$rofi_dir/screenshot.rasi" "$rofi_dir/screenshot.rasi.bspwm-setup"
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
cp -a -- \
  "$icon_font_dir/feather.ttf" \
  "$icon_font_dir/feather.ttf.bspwm-setup"
cp -a -- "$target_home/.xinitrc" "$target_home/.xinitrc.bspwm-setup"

chown -R "$target_user:$target_group" \
  "$bspwm_dir" \
  "$sxhkd_dir" \
  "$alacritty_dir" \
  "$dunst_dir" \
  "$picom_dir" \
  "$rofi_dir" \
  "$eww_dir" \
  "$zathura_dir" \
  "$gtk3_dir" \
  "$wallpaper_dir" \
  "$gtk_theme_dir" \
  "$font_dir" \
  "$icon_font_dir"
chown "$target_user:$target_group" \
  "$target_home/.gtkrc-2.0" \
  "$target_home/.gtkrc-2.0.bspwm-setup" \
  "$target_home/.zshrc" \
  "$target_home/.zshrc.bspwm-setup" \
  "$target_home/.Xresources" \
  "$target_home/.Xresources.bspwm-setup" \
  "$target_home/.xinitrc" \
  "$target_home/.xinitrc.bspwm-setup"

runuser -u "$target_user" -- fc-cache -f "$font_dir" "$icon_font_dir"

zsh_path=$(command -v zsh)
if [[ $(getent passwd "$target_user" | cut -d: -f7) != "$zsh_path" ]]; then
  usermod --shell "$zsh_path" "$target_user"
  log "Set Zsh as the login shell for $target_user."
fi

log "Installation complete."
log "Log in on a TTY and run: startx"
