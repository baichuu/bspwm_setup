#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
eww_build_dir=''
eza_tmp_dir=''
neovim_tmp_dir=''
picom_build_dir=''
greenclip_tmp_file=''

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

setup_swap() {
  local target_kib=$((8 * 1024 * 1024))
  local swapfile='/swapfile-bspwm-setup'
  local total_kib
  local missing_kib
  local missing_mib
  local available_kib
  local required_free_kib
  local swap_type

  install -m 0644 \
    "$SCRIPT_DIR/config/system/99-bspwm-setup-swap.conf" \
    /etc/sysctl.d/99-bspwm-setup-swap.conf

  if [[ -e /.dockerenv ]] ||
    systemd-detect-virt --quiet --container >/dev/null 2>&1; then
    warn 'Container detected; skipping swap activation because containers cannot manage host swap.'
    return
  fi

  sysctl --load /etc/sysctl.d/99-bspwm-setup-swap.conf >/dev/null
  total_kib=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
  [[ $total_kib =~ ^[0-9]+$ ]] || die 'Cannot determine the current swap size.'
  if ((total_kib >= target_kib)); then
    log "Existing swap is already at least 8 GiB ($((total_kib / 1024)) MiB)."
    return
  fi

  missing_kib=$((target_kib - total_kib))
  missing_mib=$(((missing_kib + 1023) / 1024))

  if [[ ! -e $swapfile ]]; then
    available_kib=$(df -Pk / | awk 'NR == 2 {print $4}')
    required_free_kib=$((missing_mib * 1024 + 2 * 1024 * 1024))
    [[ $available_kib =~ ^[0-9]+$ ]] || die 'Cannot determine free disk space for swap.'
    ((available_kib >= required_free_kib)) ||
      die "Not enough disk space to add ${missing_mib} MiB of swap while retaining a 2 GiB safety margin."

    log "Creating a ${missing_mib} MiB swap file to bring total swap to approximately 8 GiB..."
    if ! fallocate -l "${missing_mib}MiB" "$swapfile"; then
      rm -f -- "$swapfile"
      dd if=/dev/zero of="$swapfile" bs=1M count="$missing_mib" status=progress
    fi
    chmod 0600 "$swapfile"
    mkswap "$swapfile" >/dev/null
  else
    swap_type=$(blkid -p -s TYPE -o value "$swapfile" 2>/dev/null || true)
    [[ $swap_type == swap ]] ||
      die "Refusing to overwrite an existing non-swap file: $swapfile"
    chmod 0600 "$swapfile"
  fi

  if ! swapon --show=NAME --noheadings |
    awk -v path="$swapfile" '$1 == path {found=1} END {exit !found}'; then
    swapon "$swapfile"
  fi
  if ! awk -v path="$swapfile" '$1 == path && $3 == "swap" {found=1} END {exit !found}' /etc/fstab; then
    printf '%s none swap sw 0 0\n' "$swapfile" >>/etc/fstab
  fi

  total_kib=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
  ((total_kib >= target_kib)) || die 'Swap activation completed but total swap is still below 8 GiB.'
  log "Swap ready: $((total_kib / 1024)) MiB total, vm.swappiness=20."
}

link_repo_config() {
  local source=$1
  local target=$2
  local link_owner=${3:-$target_user:$target_group}
  local backup

  [[ -e $source || -L $source ]] || die "Configuration source does not exist: $source"
  mkdir -p -- "$(dirname -- "$target")"

  if [[ -L $target && $(readlink -- "$target") == "$source" ]]; then
    return
  fi

  if [[ -e $target || -L $target ]]; then
    backup="$target.bak.$(date +%Y%m%d-%H%M%S)"
    while [[ -e $backup || -L $backup ]]; do
      backup="$backup.1"
    done
    mv -- "$target" "$backup"
    warn "Moved existing configuration to: $backup"
  fi

  ln -s -- "$source" "$target"
  chown -h "$link_owner" "$target"
}

cleanup_build_dirs() {
  if [[ -n $eza_tmp_dir && $eza_tmp_dir == /tmp/bspwm-eza.* ]]; then
    rm -rf -- "$eza_tmp_dir"
    eza_tmp_dir=''
  fi
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
  if [[ -n $greenclip_tmp_file && $greenclip_tmp_file == /tmp/bspwm-greenclip.* ]]; then
    rm -f -- "$greenclip_tmp_file"
    greenclip_tmp_file=''
  fi
}

trap cleanup_build_dirs EXIT

install_eza() {
  local version='0.23.5'
  local archive='eza_x86_64-unknown-linux-gnu.tar.gz'
  local expected_sha256='35c70c5c43c29108075e58b893234c67ef585f0b53a7eaf8e9e7d4eec9f339b4'

  if command -v eza >/dev/null 2>&1 &&
    eza --version 2>/dev/null | grep -Fq "v$version"; then
    log "Using the existing Eza v$version installation: $(command -v eza)"
    return
  fi

  [[ $(dpkg --print-architecture) == amd64 ]] ||
    die "This setup supports the official Eza v$version x86-64 release only."

  eza_tmp_dir=$(mktemp -d /tmp/bspwm-eza.XXXXXX)
  log "Installing Eza v$version from its official x86-64 release..."
  curl -fL --retry 3 \
    "https://github.com/eza-community/eza/releases/download/v$version/$archive" \
    -o "$eza_tmp_dir/$archive"
  printf '%s  %s\n' "$expected_sha256" "$eza_tmp_dir/$archive" |
    sha256sum --check --status - || die "Eza v$version checksum verification failed."
  tar -xzf "$eza_tmp_dir/$archive" -C "$eza_tmp_dir"
  [[ -x $eza_tmp_dir/eza ]] || die 'The Eza release archive did not contain the expected binary.'
  install -m 0755 "$eza_tmp_dir/eza" /usr/local/bin/eza
  /usr/local/bin/eza --version 2>/dev/null | grep -Fq "v$version" ||
    die "Eza v$version verification failed."
  rm -rf -- "$eza_tmp_dir"
  eza_tmp_dir=''
}

install_greenclip() {
  local version='4.2'
  local expected_sha256='80b189fc9ce2e0a56e33be642875f5c3fb53647465f8024a541621307a6a290f'

  if command -v greenclip >/dev/null 2>&1 &&
    [[ $(greenclip --help 2>&1 | sed -n '1p') == "greenclip v$version "* ]]; then
    log "Using the existing Greenclip v$version installation: $(command -v greenclip)"
    return
  fi

  [[ $(dpkg --print-architecture) == amd64 ]] ||
    die "The official Greenclip v$version static binary is available only for amd64."

  greenclip_tmp_file=$(mktemp /tmp/bspwm-greenclip.XXXXXX)
  log "Installing Greenclip v$version from its official static release..."
  curl -fL --retry 3 \
    "https://github.com/erebe/greenclip/releases/download/v$version/greenclip" \
    -o "$greenclip_tmp_file"
  printf '%s  %s\n' "$expected_sha256" "$greenclip_tmp_file" |
    sha256sum --check --status - || die "Greenclip v$version checksum verification failed."
  install -m 0755 "$greenclip_tmp_file" /usr/local/bin/greenclip
  rm -f -- "$greenclip_tmp_file"
  greenclip_tmp_file=''
}

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
  config/flameshot/flameshot.ini \
  config/greenclip/greenclip.toml \
  config/eww/eww.scss \
  config/eww/eww.yuck \
  config/eww/scripts/cpu \
  config/eww/scripts/brightness-control \
  config/eww/scripts/memory \
  config/eww/scripts/powermenu \
  config/eww/scripts/screenshot \
  config/eww/scripts/updates \
  config/eww/scripts/volume-status \
  config/fontconfig/50-inter-ui.conf \
  config/fonts/feather.ttf \
  config/fonts/IosevkaNerdFont-Regular.ttf \
  config/gtk-2.0/gtkrc \
  config/gtk-3.0/settings.ini \
  config/npm/npmrc \
  config/picom/picom.conf \
  config/rofi/launcher.rasi \
  config/rofi/clipboard.rasi \
  config/rofi/powermenu.rasi \
  config/rofi/screenshot.rasi \
  config/sxhkd/sxhkdrc \
  config/system/99-bspwm-setup-swap.conf \
  config/wallpaper/bspwm-wallpaper.png \
  config/x11/90-touchpad-tapping.conf \
  config/x11/Xresources \
  config/x11/xinitrc \
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
  xserver-xorg-input-libinput
  bspwm
  sxhkd
  alacritty
  rofi
  lxappearance
  chromium
  chromium-sandbox
  dunst
  feh
  flameshot
  xclip
  zathura
  zathura-pdf-poppler
  zsh
  nodejs
  npm
  rclone
  procps
  util-linux
  pipewire
  pipewire-pulse
  wireplumber
  papirus-icon-theme
  hicolor-icon-theme
  librsvg2-common
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
  fonts-inter-variable
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
command -v rclone >/dev/null 2>&1 || die 'rclone installation failed.'
log "Verified $(rclone version | sed -n '1p')."
setup_swap
install_eza
[[ -r /usr/share/icons/Papirus-Dark/index.theme ]] ||
  die "Papirus-Dark was installed without its icon theme index."
gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
gtk-update-icon-cache -f /usr/share/icons/Papirus >/dev/null 2>&1 || true
gtk-update-icon-cache -f /usr/share/icons/Papirus-Dark >/dev/null 2>&1 || true
install_greenclip
install_neovim
install_picom
install_eww

config_dir="$target_home/.config"
fontconfig_dir="$config_dir/fontconfig/conf.d"
wallpaper_dir="$target_home/.local/share/backgrounds"
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
  "$target_home/.cache" \
  "$target_home/.cache/npm" \
  "$target_home/.npm-global" \
  "$target_home/.npm-global/bin" \
  "$target_home/Pictures" \
  "$target_home/Pictures/Screenshots" \
  "$target_home/.themes"
install -d -m 0755 -o "$target_user" -g "$target_group" \
  "$fontconfig_dir" \
  "$wallpaper_dir" \
  "$font_dir" \
  "$icon_font_dir"
install -d -m 0755 /etc/X11/xorg.conf.d

log "Linking the starter configuration from the repository for $target_user..."
link_repo_config \
  "$SCRIPT_DIR/config/x11/90-touchpad-tapping.conf" \
  /etc/X11/xorg.conf.d/90-touchpad-tapping.conf \
  root:root
link_repo_config "$SCRIPT_DIR/config/bspwm" "$config_dir/bspwm"
link_repo_config "$SCRIPT_DIR/config/sxhkd" "$config_dir/sxhkd"
link_repo_config "$SCRIPT_DIR/config/alacritty" "$config_dir/alacritty"
link_repo_config "$SCRIPT_DIR/config/dunst" "$config_dir/dunst"
link_repo_config "$SCRIPT_DIR/config/flameshot" "$config_dir/flameshot"
link_repo_config "$SCRIPT_DIR/config/greenclip/greenclip.toml" "$config_dir/greenclip.toml"
link_repo_config "$SCRIPT_DIR/config/picom" "$config_dir/picom"
link_repo_config "$SCRIPT_DIR/config/rofi" "$config_dir/rofi"
link_repo_config "$SCRIPT_DIR/config/eww" "$config_dir/eww"
link_repo_config "$SCRIPT_DIR/config/zathura" "$config_dir/zathura"
link_repo_config "$SCRIPT_DIR/config/gtk-3.0" "$config_dir/gtk-3.0"
link_repo_config "$SCRIPT_DIR/config/fontconfig/50-inter-ui.conf" "$fontconfig_dir/50-inter-ui.conf"
link_repo_config "$SCRIPT_DIR/config/gtk-2.0/gtkrc" "$target_home/.gtkrc-2.0"
link_repo_config "$SCRIPT_DIR/config/npm/npmrc" "$target_home/.npmrc"
link_repo_config "$SCRIPT_DIR/config/zsh/.zshrc" "$target_home/.zshrc"
link_repo_config "$SCRIPT_DIR/config/x11/Xresources" "$target_home/.Xresources"
link_repo_config "$SCRIPT_DIR/config/x11/xinitrc" "$target_home/.xinitrc"
link_repo_config "$SCRIPT_DIR/config/wallpaper/bspwm-wallpaper.png" "$wallpaper_dir/bspwm-wallpaper.png"
link_repo_config "$SCRIPT_DIR/config/gtk-theme/siduck-onedark" "$target_home/.themes/siduck-onedark"
link_repo_config "$SCRIPT_DIR/config/fonts/IosevkaNerdFont-Regular.ttf" "$font_dir/IosevkaNerdFont-Regular.ttf"
link_repo_config "$SCRIPT_DIR/config/fonts/feather.ttf" "$icon_font_dir/feather.ttf"

chown -R "$target_user:$target_group" \
  "$target_home/.cache/npm" \
  "$target_home/.npm-global"

runuser -u "$target_user" -- fc-cache -f "$font_dir" "$icon_font_dir"

zsh_path=$(command -v zsh)
if [[ $(getent passwd "$target_user" | cut -d: -f7) != "$zsh_path" ]]; then
  usermod --shell "$zsh_path" "$target_user"
  log "Set Zsh as the login shell for $target_user."
fi

log "Installation complete."
log "Log in on a TTY and run: startx"
