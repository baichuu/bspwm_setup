#!/usr/bin/env bash

set -Eeuo pipefail

readonly VIVADO_VERSION='2025.2'
readonly DOWNLOAD_URL='https://www.amd.com/en/support/downloads/adaptive-socs-and-fpgas/development-tools/2025-2.html'
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
work_dir=''
settings=''

log() {
  printf '\033[1;32m[install-vivado.sh]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[install-vivado.sh]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m[install-vivado.sh]\033[0m %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n $work_dir && $work_dir == /tmp/vivado-2025.2.* ]]; then
    rm -rf -- "$work_dir"
  fi
}

trap cleanup EXIT

find_vivado_settings() {
  local candidate
  local root
  local search_roots=(
    "$HOME/AMD"
    "$HOME/Xilinx"
    /tools/AMD
    /tools/Xilinx
    /opt/AMD
    /opt/Xilinx
  )

  settings=''
  for root in "${search_roots[@]}"; do
    [[ -d $root ]] || continue
    candidate=$(find "$root" -maxdepth 7 -type f -path '*/Vivado/settings64.sh' -print 2>/dev/null |
      grep -F "/$VIVADO_VERSION/" | sort -V | tail -n 1 || true)
    [[ -n $candidate ]] && settings=$candidate
  done

  [[ -n $settings ]] ||
    die "Vivado $VIVADO_VERSION settings64.sh was not found under ~/AMD, ~/Xilinx, /tools, or /opt."
}

ensure_vivado_locale() {
  if locale -a 2>/dev/null | grep -Fqi 'en_US.utf8'; then
    log 'Required Vivado locale is available: en_US.UTF-8'
    return
  fi

  log 'Generating the en_US.UTF-8 locale required by Vivado...'
  sudo -v
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends locales
  sudo locale-gen en_US.UTF-8
  locale -a 2>/dev/null | grep -Fqi 'en_US.utf8' ||
    die 'Failed to generate the en_US.UTF-8 locale required by Vivado.'
  log 'Required Vivado locale is ready: en_US.UTF-8'
}

remove_amd_desktop_entries() {
  local candidate
  local removed=0

  while IFS= read -r -d '' candidate; do
    rm -f -- "$candidate"
    removed=$((removed + 1))
  done < <(
    find "$applications_dir" -maxdepth 1 -type f \
      \( -name "Add Design Tools or Devices $VIVADO_VERSION"'_*.desktop' \
      -o -name "Manage Licenses $VIVADO_VERSION"'_*.desktop' \
      -o -name "Uninstall $VIVADO_VERSION"'_*.desktop' \
      -o -name 'Uninstall Xilinx Information Center_*.desktop' \
      -o -name "Vitis $VIVADO_VERSION"'_*.desktop' \
      -o -name "Vivado $VIVADO_VERSION"'_*.desktop' \
      -o -name "Vivado $VIVADO_VERSION Tcl Shell"'_*.desktop' \
      -o -name 'Xilinx Information Center_*.desktop' \) -print0
  )
  log "Removed $removed AMD-generated desktop shortcut(s)."
}

create_vivado_launcher() {
  local batch_helper
  local desktop_file
  local found_icon
  local icon='applications-engineering'
  local vivado_config_dir="$HOME/.config/vivado"
  local vivado_root
  local wrapper

  local_bin_dir="$HOME/.local/bin"
  applications_dir="$HOME/.local/share/applications"
  install -d -m 0755 "$vivado_config_dir" "$local_bin_dir" "$applications_dir"
  ln -sfn -- "$settings" "$vivado_config_dir/settings64.sh"

  wrapper="$local_bin_dir/vivado-$VIVADO_VERSION"
  sed "s|@SETTINGS@|$vivado_config_dir/settings64.sh|g" >"$wrapper" <<'EOF'
#!/usr/bin/env bash

launch_log="${XDG_CACHE_HOME:-$HOME/.cache}/vivado-launch.log"
mkdir -p -- "$(dirname -- "$launch_log")"
: >"$launch_log"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

if ! source "@SETTINGS@" >>"$launch_log" 2>&1; then
  printf 'Failed to load the Vivado environment. See %s\n' "$launch_log" >&2
  exit 1
fi
exec vivado "$@" >>"$launch_log" 2>&1
EOF
  chmod 0755 "$wrapper"

  batch_helper="$local_bin_dir/vivado-batch"
  install -m 0755 "$SCRIPT_DIR/config/vivado/vivado-batch" "$batch_helper"

  vivado_root=$(cd -- "$(dirname -- "$settings")" && pwd)
  found_icon=$(find "$vivado_root" -maxdepth 6 -type f \
    \( -iname '*vivado*.png' -o -iname '*vivado*.svg' \) -print 2>/dev/null | head -n 1 || true)
  [[ -z $found_icon ]] || icon=$found_icon

  remove_amd_desktop_entries
  desktop_file="$applications_dir/amd-vivado-2025.2.desktop"
  sed -e "s|@EXEC@|$wrapper|g" -e "s|@ICON@|$icon|g" \
    -e "s|@HOME@|$HOME|g" >"$desktop_file" <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=AMD Vivado 2025.2
Comment=FPGA design, synthesis, implementation, and analysis
Exec=@EXEC@
TryExec=@EXEC@
Path=@HOME@
Icon=@ICON@
Terminal=false
Categories=Development;Electronics;
StartupNotify=true
StartupWMClass=Vivado
EOF
  chmod 0644 "$desktop_file"
  if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$desktop_file"
  fi
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$applications_dir"
  fi
  rm -f -- "$HOME/.cache/rofi3.druncache"

  log "Vivado environment: $settings"
  log 'Rofi application entry ready: AMD Vivado 2025.2'
  log "Vivado batch helper ready: $batch_helper"
  log "GUI launch log: $HOME/.cache/vivado-launch.log"
}

usage() {
  cat <<EOF
Usage:
  ./install-vivado.sh /path/to/FPGAs_AdaptiveSoCs_Unified_2025.2_*_Lin64.bin
  ./install-vivado.sh --repair-launcher

Prepare Ubuntu, launch the official Vivado ML Standard 2025.2 installer, then
create a Zsh environment link and an application entry for Rofi.

Use --repair-launcher after Vivado is already installed to remove the extra AMD
shortcuts and recreate the repository launcher without running the installer.

Download the Linux self-extracting web installer first:
$DOWNLOAD_URL

Run this script as your regular desktop user, not with sudo.
EOF
}

[[ ${1:-} != -h && ${1:-} != --help ]] || {
  usage
  exit 0
}

(($# == 1)) || {
  usage >&2
  exit 2
}

[[ $EUID -ne 0 ]] || die 'Run this script as your regular user, without sudo.'

[[ -r /etc/os-release ]] || die 'Cannot detect the operating system.'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || die "Ubuntu is required (detected: ${ID:-unknown})."
[[ $(uname -m) == x86_64 ]] || die 'Vivado 2025.2 requires an x86-64 machine.'

[[ -x $SCRIPT_DIR/config/vivado/vivado-batch ]] ||
  die 'Missing batch helper: config/vivado/vivado-batch'

if [[ $1 == --repair-launcher ]]; then
  log 'Locating the existing Vivado environment...'
  find_vivado_settings
  ensure_vivado_locale
  create_vivado_launcher
  log 'Launcher repair complete. Open Rofi and select AMD Vivado 2025.2.'
  exit 0
fi

[[ -n ${DISPLAY:-} ]] || die 'Start X11 with startx, then run this script inside Alacritty.'

installer=$1
[[ -f $installer ]] || die "Installer not found: $installer"
installer=$(realpath -- "$installer")
[[ $installer == *.bin ]] || die 'Expected the AMD Linux self-extracting .bin installer.'
[[ ${installer##*/} == *2025.2* ]] ||
  die 'This script requires the Vivado 2025.2 Linux installer.'

if [[ ${VERSION_ID:-} == 24.04 && ${VERSION:-} != *'24.04.2'* ]]; then
  warn "AMD officially validated Vivado 2025.2 only through Ubuntu 24.04.2; detected ${VERSION:-24.04}."
fi

available_kib=$(df -Pk "$HOME" | awk 'NR == 2 {print $4}')
if [[ $available_kib =~ ^[0-9]+$ ]] && ((available_kib < 100 * 1024 * 1024)); then
  warn 'Less than 100 GiB is free. Vivado plus project runs can require substantial space.'
fi

log 'Installing small host utilities needed by the installer...'
sudo -v
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates \
  desktop-file-utils \
  locales \
  unzip \
  zip
sudo locale-gen en_US.UTF-8

work_dir=$(mktemp -d /tmp/vivado-2025.2.XXXXXX)
image_dir="$work_dir/image"

log 'Extracting the AMD installer into a temporary directory...'
chmod u+x "$installer"
"$installer" --keep --noexec --target "$image_dir"

install_libs=$(find "$image_dir" -maxdepth 3 -type f -name installLibs.sh -print -quit)
xsetup=$(find "$image_dir" -maxdepth 3 -type f -name xsetup -print -quit)
[[ -n $install_libs ]] || die 'The installer image does not contain installLibs.sh.'
[[ -n $xsetup ]] || die 'The installer image does not contain xsetup.'

log 'Installing the exact Linux libraries requested by the AMD image...'
sudo bash "$install_libs"

cat <<'EOF'

Installer choices for the free DominoSearch/OpenEye setup:
  1. Download and Install Now
  2. Vivado
  3. Vivado ML Standard Edition 2025.2
  4. Install only Zynq UltraScale+ MPSoC device support
  5. Do not select Vitis, PetaLinux, Model Composer, or DocNav
  6. Prefer a path without spaces, for example: ~/AMD

For provisional reports use an XCZU1-XCZU7 device such as the XCZU7EV.
The free Standard Edition cannot target the paper's ZU19EG.
EOF

chmod u+x "$xsetup"
"$xsetup"

log 'Locating the installed Vivado environment...'
find_vivado_settings
ensure_vivado_locale
create_vivado_launcher
log 'Open a new terminal, or run: source ~/.config/vivado/settings64.sh'
