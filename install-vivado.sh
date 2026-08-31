#!/usr/bin/env bash

set -Eeuo pipefail

readonly VIVADO_VERSION='2025.2'
readonly DOWNLOAD_URL='https://www.amd.com/en/support/downloads/adaptive-socs-and-fpgas/development-tools/2025-2.html'
work_dir=''

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

usage() {
  cat <<EOF
Usage: ./install-vivado.sh /path/to/FPGAs_AdaptiveSoCs_Unified_2025.2_*_Lin64.bin

Prepare Ubuntu, launch the official Vivado ML Standard 2025.2 installer, then
create a Zsh environment link and an application entry for Rofi.

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
[[ -n ${DISPLAY:-} ]] || die 'Start X11 with startx, then run this script inside Alacritty.'

installer=$1
[[ -f $installer ]] || die "Installer not found: $installer"
installer=$(realpath -- "$installer")
[[ $installer == *.bin ]] || die 'Expected the AMD Linux self-extracting .bin installer.'
[[ ${installer##*/} == *2025.2* ]] ||
  die 'This script requires the Vivado 2025.2 Linux installer.'

[[ -r /etc/os-release ]] || die 'Cannot detect the operating system.'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || die "Ubuntu is required (detected: ${ID:-unknown})."
[[ $(uname -m) == x86_64 ]] || die 'Vivado 2025.2 requires an x86-64 machine.'

if [[ ${VERSION_ID:-} == 24.04 && ${VERSION:-} != *'24.04.2'* ]]; then
  warn "AMD officially validated Vivado 2025.2 only through Ubuntu 24.04.2; detected ${VERSION:-24.04}."
fi

available_kib=$(df -Pk "$HOME" | awk 'NR == 2 {print $4}')
if [[ $available_kib =~ ^[0-9]+$ ]] && ((available_kib < 80 * 1024 * 1024)); then
  warn 'Less than 80 GiB is free. Vivado plus project runs can require substantial space.'
fi

log 'Installing small host utilities needed by the installer...'
sudo -v
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates \
  desktop-file-utils \
  unzip \
  zip

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
search_roots=(
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
    grep '/2025\.2/' | sort -V | tail -n 1 || true)
  [[ -n $candidate ]] && settings=$candidate
done

if [[ -z $settings ]]; then
  die 'Vivado 2025.2 settings64.sh was not found. Install under ~/AMD or add the custom location to search_roots in this script.'
fi

vivado_config_dir="$HOME/.config/vivado"
local_bin_dir="$HOME/.local/bin"
applications_dir="$HOME/.local/share/applications"
install -d -m 0755 "$vivado_config_dir" "$local_bin_dir" "$applications_dir"
ln -sfn -- "$settings" "$vivado_config_dir/settings64.sh"

wrapper="$local_bin_dir/vivado-$VIVADO_VERSION"
sed "s|@SETTINGS@|$vivado_config_dir/settings64.sh|g" >"$wrapper" <<'EOF'
#!/usr/bin/env bash
set -e
source "@SETTINGS@"
exec vivado "$@"
EOF
chmod 0755 "$wrapper"

icon='applications-engineering'
vivado_root=$(cd -- "$(dirname -- "$settings")" && pwd)
found_icon=$(find "$vivado_root" -maxdepth 6 -type f \
  \( -iname '*vivado*.png' -o -iname '*vivado*.svg' \) -print 2>/dev/null | head -n 1)
[[ -z $found_icon ]] || icon=$found_icon

desktop_file="$applications_dir/amd-vivado-2025.2.desktop"
sed -e "s|@EXEC@|$wrapper|g" -e "s|@ICON@|$icon|g" >"$desktop_file" <<'EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=AMD Vivado 2025.2
Comment=FPGA design, synthesis, implementation, and analysis
Exec=@EXEC@
Icon=@ICON@
Terminal=false
Categories=Development;Electronics;
StartupNotify=true
StartupWMClass=Vivado
EOF
chmod 0644 "$desktop_file"
desktop-file-validate "$desktop_file"
update-desktop-database "$applications_dir"

log "Vivado environment: $settings"
log 'Rofi application entry created: AMD Vivado 2025.2'
log 'Open a new terminal, or run: source ~/.config/vivado/settings64.sh'
