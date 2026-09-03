#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
eww_build_dir=''
eza_tmp_dir=''
flameshot_tmp_file=''
lazygit_tmp_dir=''
neovim_tmp_dir=''
picom_build_dir=''
greenclip_tmp_file=''
transient_build_packages=()

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

[[ -r $SCRIPT_DIR/lib/config-links.sh ]] || die 'Missing shared config manifest: lib/config-links.sh'
# shellcheck source=lib/config-links.sh
source "$SCRIPT_DIR/lib/config-links.sh"

usage() {
  cat <<EOF
Usage: sudo ./$SCRIPT_NAME [--user USER] [--with-npm]

Install a bspwm desktop and common desktop utilities on Ubuntu Server minimal.

Options:
  --user USER    Configure bspwm for USER (default: the user who called sudo)
  --with-npm     Also install Node.js and npm (not needed by DominoSearch)
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

install_transient_build_packages() {
  local package

  for package in "$@"; do
    if [[ $(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true) != installed ]]; then
      transient_build_packages+=("$package")
    fi
  done
  apt-get install -y --no-install-recommends "$@"
}

cleanup_package_data() {
  log 'Removing unused packages and APT download/index caches...'
  if ((${#transient_build_packages[@]})); then
    apt-get purge -y "${transient_build_packages[@]}"
  fi
  apt-get autoremove -y --purge
  apt-get clean
  if [[ -d /var/lib/apt/lists ]]; then
    find /var/lib/apt/lists -mindepth 1 -delete
  fi
}

cleanup_build_dirs() {
  if [[ -n $eza_tmp_dir && $eza_tmp_dir == /tmp/bspwm-eza.* ]]; then
    rm -rf -- "$eza_tmp_dir"
    eza_tmp_dir=''
  fi
  if [[ -n $flameshot_tmp_file && $flameshot_tmp_file == /tmp/bspwm-flameshot.* ]]; then
    rm -f -- "$flameshot_tmp_file"
    flameshot_tmp_file=''
  fi
  if [[ -n $lazygit_tmp_dir && $lazygit_tmp_dir == /tmp/bspwm-lazygit.* ]]; then
    rm -rf -- "$lazygit_tmp_dir"
    lazygit_tmp_dir=''
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

install_flameshot() {
  local version='13.3.0'
  local asset="flameshot-$version-1.ubuntu-24.04.amd64.deb"
  local expected_sha256='e6dcec9e817c49776549f8c6998bcaff38f3af77ceb5f7f98c655e55e137b24d'

  if command -v flameshot >/dev/null 2>&1 &&
    flameshot --version 2>&1 | grep -Fq "$version"; then
    log "Using the existing Flameshot v$version installation: $(command -v flameshot)"
    return
  fi

  [[ $(dpkg --print-architecture) == amd64 ]] ||
    die "The official Flameshot v$version Ubuntu package is available only for amd64."

  flameshot_tmp_file=$(mktemp /tmp/bspwm-flameshot.XXXXXX.deb)
  log "Installing Flameshot v$version from its official Ubuntu 24.04 package..."
  curl -fL --retry 3 \
    "https://github.com/flameshot-org/flameshot/releases/download/v$version/$asset" \
    -o "$flameshot_tmp_file"
  printf '%s  %s\n' "$expected_sha256" "$flameshot_tmp_file" |
    sha256sum --check --status - || die "Flameshot v$version checksum verification failed."
  apt-get install -y --no-install-recommends "$flameshot_tmp_file"
  flameshot --version 2>&1 | grep -Fq "$version" ||
    die "Flameshot v$version verification failed."
  rm -f -- "$flameshot_tmp_file"
  flameshot_tmp_file=''
}

install_lazygit() {
  local version='0.64.1'
  local archive="lazygit_${version}_linux_x86_64.tar.gz"
  local expected_sha256='f8ea237c41f194cd799b48505518bfdaae4edf5a2ad6bd3d898e939785ee4532'

  if command -v lazygit >/dev/null 2>&1 &&
    lazygit --version 2>/dev/null | grep -Fq "version=$version"; then
    log "Using the existing LazyGit v$version installation: $(command -v lazygit)"
    return
  fi

  [[ $(dpkg --print-architecture) == amd64 ]] ||
    die "This setup supports the official LazyGit v$version x86-64 release only."

  lazygit_tmp_dir=$(mktemp -d /tmp/bspwm-lazygit.XXXXXX)
  log "Installing LazyGit v$version from its official x86-64 release..."
  curl -fL --retry 3 \
    "https://github.com/jesseduffield/lazygit/releases/download/v$version/$archive" \
    -o "$lazygit_tmp_dir/$archive"
  printf '%s  %s\n' "$expected_sha256" "$lazygit_tmp_dir/$archive" |
    sha256sum --check --status - || die "LazyGit v$version checksum verification failed."
  tar -xzf "$lazygit_tmp_dir/$archive" -C "$lazygit_tmp_dir"
  [[ -x $lazygit_tmp_dir/lazygit ]] ||
    die 'The LazyGit release archive did not contain the expected binary.'
  install -m 0755 "$lazygit_tmp_dir/lazygit" /usr/local/bin/lazygit
  /usr/local/bin/lazygit --version 2>/dev/null | grep -Fq "version=$version" ||
    die "LazyGit v$version verification failed."
  rm -rf -- "$lazygit_tmp_dir"
  lazygit_tmp_dir=''
}

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
  install_transient_build_packages \
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
  install_transient_build_packages \
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
install_npm=false

while (($#)); do
  case $1 in
  --user)
    (($# >= 2)) || die "--user requires a user name."
    target_user=$2
    shift 2
    ;;
  --with-npm)
    install_npm=true
    shift
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

validate_desktop_config_sources

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
  xclip
  zathura
  zathura-pdf-poppler
  zsh
  git
  locales
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

if $install_npm; then
  packages+=(nodejs npm)
fi

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
log 'Generating the en_US.UTF-8 locale required by Vivado...'
locale-gen en_US.UTF-8
locale -a 2>/dev/null | grep -Fqi 'en_US.utf8' ||
  die 'Failed to generate the en_US.UTF-8 locale required by Vivado.'
command -v rclone >/dev/null 2>&1 || die 'rclone installation failed.'
log "Verified $(rclone version | sed -n '1p')."
setup_swap
install_flameshot
install_eza
install_lazygit
[[ -r /usr/share/icons/Papirus-Dark/index.theme ]] ||
  die "Papirus-Dark was installed without its icon theme index."
gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
gtk-update-icon-cache -f /usr/share/icons/Papirus >/dev/null 2>&1 || true
gtk-update-icon-cache -f /usr/share/icons/Papirus-Dark >/dev/null 2>&1 || true
install_greenclip
install_neovim
install_picom
install_eww

font_dir="$target_home/.local/share/fonts/Iosevka"
icon_font_dir="$target_home/.local/share/fonts/Icons"
log "Linking the starter configuration from the repository for $target_user..."
install_desktop_config_links

runuser -u "$target_user" -- fc-cache -f "$font_dir" "$icon_font_dir"

zsh_path=$(command -v zsh)
if [[ $(getent passwd "$target_user" | cut -d: -f7) != "$zsh_path" ]]; then
  usermod --shell "$zsh_path" "$target_user"
  log "Set Zsh as the login shell for $target_user."
fi

cleanup_package_data
log "Installation complete."
log "Log out, then log in on TTY1; Zsh will start X automatically."
