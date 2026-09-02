#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
failures=0
warnings=0
config_only=false
sources_only=false

pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; }
warn() {
  warnings=$((warnings + 1))
  printf '\033[1;33mWARN\033[0m %s\n' "$*" >&2
}
fail() {
  failures=$((failures + 1))
  printf '\033[1;31mFAIL\033[0m %s\n' "$*" >&2
}
die() {
  printf '\033[1;31m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 2
}

usage() {
  cat <<EOF
Usage: ./$SCRIPT_NAME [--user USER] [--config-only | --sources-only]

Read-only health check for repository sources, installed symlinks, commands,
swap, and pinned tools. --config-only skips package and runtime checks;
--sources-only checks only repository files and their executable bits.
EOF
}

target_user="${SUDO_USER:-${USER:-}}"
while (($#)); do
  case $1 in
  --user)
    (($# >= 2)) || die '--user requires a user name.'
    target_user=$2
    shift 2
    ;;
  --config-only)
    config_only=true
    shift
    ;;
  --sources-only)
    sources_only=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "Unknown option: $1" ;;
  esac
done

[[ -n $target_user ]] || die 'Cannot determine the target user.'
getent passwd "$target_user" >/dev/null || die "User does not exist: $target_user"
target_home=$(getent passwd "$target_user" | cut -d: -f6)
target_group=$(id -gn "$target_user")

# The shared file expects these names, but this checker never mutates links.
log() { :; }
# shellcheck source=lib/config-links.sh
source "$SCRIPT_DIR/lib/config-links.sh"

while IFS= read -r relative; do
  [[ -n $relative ]] || continue
  if [[ -r $SCRIPT_DIR/$relative ]]; then
    pass "source $relative"
  else
    fail "missing source $relative"
  fi
done < <(desktop_config_sources)

executable_sources=(
  config/bspwm/bspwmrc
  config/eww/scripts/brightness-control
  config/eww/scripts/cpu
  config/eww/scripts/memory
  config/eww/scripts/powermenu
  config/eww/scripts/screenshot
  config/eww/scripts/updates
  config/eww/scripts/volume-status
  config/vivado/vivado-batch
  config/x11/xinitrc
  setup-networkmanager.sh
)
for relative in "${executable_sources[@]}"; do
  if [[ -x $SCRIPT_DIR/$relative ]]; then
    pass "executable $relative"
  else
    fail "$relative is not executable"
  fi
done

shell_sources=(
  install-bspwm.sh
  install-openeye.sh
  install-vivado.sh
  setup-networkmanager.sh
  apply-config.sh
  check-setup.sh
  lib/config-links.sh
  config/bspwm/bspwmrc
  config/eww/scripts/brightness-control
  config/eww/scripts/cpu
  config/eww/scripts/memory
  config/eww/scripts/powermenu
  config/eww/scripts/screenshot
  config/eww/scripts/updates
  config/eww/scripts/volume-status
  config/vivado/vivado-batch
  config/x11/xinitrc
)
shell_paths=()
for relative in "${shell_sources[@]}"; do
  shell_paths+=("$SCRIPT_DIR/$relative")
done
if bash -n "${shell_paths[@]}"; then
  pass 'shell syntax'
else
  fail 'shell syntax validation failed'
fi

if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$SCRIPT_DIR" diff --check --; then
    pass 'git diff whitespace'
  else
    fail 'git diff contains whitespace errors'
  fi
else
  warn 'Git worktree not detected; skipped diff whitespace validation'
fi

if $sources_only; then
  printf '\nResult: %d failure(s), %d warning(s).\n' "$failures" "$warnings"
  ((failures == 0))
  exit
fi

while IFS='|' read -r source target owner; do
  [[ -n $source ]] || continue
  if [[ ! -L $target ]]; then
    fail "$target is not a symlink"
  elif [[ $(readlink -- "$target") != "$source" ]]; then
    fail "$target points to $(readlink -- "$target"), expected $source"
  elif [[ ! -e $target ]]; then
    fail "$target is a broken symlink"
  else
    pass "link $target"
  fi
done < <(desktop_config_links)

if ! $config_only; then
  required_commands=(
    alacritty bspc bspwm chromium dunst eww eza flameshot greenclip nmcli nmtui
    netplan nvim npm picom pipewire pipewire-pulse rclone rofi sxhkd wireplumber
    xclip zathura zsh
  )
  for command_name in "${required_commands[@]}"; do
    if command -v "$command_name" >/dev/null 2>&1; then
      pass "command $command_name"
    else
      fail "missing command $command_name"
    fi
  done

  if command -v eza >/dev/null 2>&1; then
    eza --version 2>/dev/null | grep -Fq 'v0.23.5' || fail 'Eza is not pinned v0.23.5'
  fi
  if command -v nvim >/dev/null 2>&1; then
    [[ $(nvim --version 2>/dev/null | sed -n '1p') == 'NVIM v0.11.7' ]] ||
      fail 'Neovim is not pinned v0.11.7'
  fi
  if command -v picom >/dev/null 2>&1; then
    picom --version 2>/dev/null | grep -Fq 'v13' || fail 'Picom is not pinned v13'
  fi

  if command -v netplan >/dev/null 2>&1; then
    effective_network=$(netplan get 2>/dev/null || true)
    if printf '%s\n' "$effective_network" | grep -Eq 'renderer:[[:space:]]+NetworkManager' &&
      ! printf '%s\n' "$effective_network" | grep -Eiq 'renderer:[[:space:]]+networkd'; then
      pass 'Netplan renderer is NetworkManager'
    else
      fail 'Netplan is not exclusively rendered by NetworkManager'
    fi
  else
    fail 'Netplan command is missing'
  fi
  if command -v nmcli >/dev/null 2>&1 &&
    nmcli -t -f RUNNING general 2>/dev/null | grep -Fxq running; then
    pass 'NetworkManager is running'
  else
    fail 'NetworkManager is not running'
  fi

  swap_kib=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
  if [[ $swap_kib =~ ^[0-9]+$ ]] && ((swap_kib >= 8 * 1024 * 1024)); then
    pass "swap total is $((swap_kib / 1024)) MiB"
  else
    warn "swap total is below 8 GiB (${swap_kib:-unknown} KiB)"
  fi

  if [[ -r $target_home/.config/vivado/settings64.sh ]]; then
    pass 'Vivado environment link exists'
  else
    warn 'Vivado is not installed or its environment link is missing'
  fi
  if [[ -f $target_home/Projects/OpenEye/environment.json ]]; then
    pass 'OpenEye environment manifest exists'
  else
    warn 'OpenEye environment manifest is not present'
  fi
fi

printf '\nResult: %d failure(s), %d warning(s).\n' "$failures" "$warnings"
((failures == 0))
