#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_SOURCE="$SCRIPT_DIR/config/network/99-bspwm-networkmanager.yaml"
readonly CONFIG_TARGET='/etc/netplan/99-bspwm-networkmanager.yaml'
skip_package_install=false
rollback_dir=''
had_previous_config=false
migration_pending=false

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
Usage: sudo ./$SCRIPT_NAME [--skip-package-install]

Switch an Ubuntu Server Netplan configuration from the networkd default to
NetworkManager. Existing interface, DHCP, DNS, Wi-Fi, and static-address
definitions remain in their original Netplan files.

The change is applied through an interactive 60-second 'netplan try'. Confirm
only after checking that networking still works; otherwise it is rolled back.
EOF
}

restore_previous_config() {
  rm -f -- "$CONFIG_TARGET"
  if $had_previous_config; then
    cp -a -- "$rollback_dir/previous-config" "$CONFIG_TARGET"
  fi
  if netplan generate; then
    netplan apply || warn 'Netplan generated the rollback configuration but could not apply it completely.'
  else
    warn 'Could not generate the previous Netplan configuration during rollback.'
  fi
}

cleanup() {
  local status=$?

  trap - EXIT
  if $migration_pending; then
    warn 'An unexpected error interrupted migration; restoring the previous Netplan configuration.'
    set +e
    restore_previous_config
    set -e
  fi
  if [[ -n $rollback_dir && $rollback_dir == /tmp/bspwm-networkmanager.* ]]; then
    rm -rf -- "$rollback_dir"
  fi
  exit "$status"
}

rollback_and_die() {
  local message=$1

  restore_previous_config
  migration_pending=false
  die "$message"
}

trap cleanup EXIT

while (($#)); do
  case $1 in
  --skip-package-install)
    skip_package_install=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "Unknown option: $1" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "Run with sudo: sudo ./$SCRIPT_NAME"
[[ -r /etc/os-release ]] || die 'Cannot detect the operating system.'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 24.04 ]] ||
  die "This migration supports Ubuntu 24.04 only (detected: ${PRETTY_NAME:-unknown})."
[[ -r $CONFIG_SOURCE ]] || die 'Missing NetworkManager Netplan configuration in the repository.'

if [[ -e /.dockerenv ]] || systemd-detect-virt --quiet --container >/dev/null 2>&1; then
  warn 'Container detected; skipping host network renderer migration.'
  exit 0
fi

[[ -z ${SSH_CONNECTION:-} && -z ${SSH_TTY:-} ]] ||
  die 'Refusing to change the network renderer over SSH. Run this script from the physical machine TTY.'

if ! $skip_package_install; then
  log 'Installing NetworkManager from Ubuntu packages...'
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    network-manager \
    network-manager-gnome \
    lxpolkit \
    wpasupplicant
fi

for required_command in netplan nmcli systemctl; do
  command -v "$required_command" >/dev/null 2>&1 ||
    die "Required command is missing: $required_command"
done

if [[ ! -t 0 ]]; then
  die 'An interactive local TTY is required so netplan try can confirm or roll back safely.'
fi

if [[ -f $CONFIG_TARGET ]] && cmp -s "$CONFIG_SOURCE" "$CONFIG_TARGET"; then
  current_effective_config=$(netplan get 2>/dev/null || true)
  systemctl enable NetworkManager.service >/dev/null
  if printf '%s\n' "$current_effective_config" | grep -Eq 'renderer:[[:space:]]+NetworkManager' &&
    ! printf '%s\n' "$current_effective_config" | grep -Eiq 'renderer:[[:space:]]+networkd' &&
    systemctl is-active --quiet NetworkManager.service &&
    nmcli -t -f RUNNING general 2>/dev/null | grep -Fxq running; then
    log 'NetworkManager is already the configured and running Netplan renderer.'
    nmcli device status
    exit 0
  fi
fi

rollback_dir=$(mktemp -d /tmp/bspwm-networkmanager.XXXXXX)
install -d -m 0755 /etc/netplan
if [[ (-e $CONFIG_TARGET || -L $CONFIG_TARGET) && ! -f $CONFIG_TARGET ]]; then
  die "Refusing to replace a non-file Netplan target: $CONFIG_TARGET"
fi
if [[ -e $CONFIG_TARGET || -L $CONFIG_TARGET ]]; then
  cp -a -- "$CONFIG_TARGET" "$rollback_dir/previous-config"
  had_previous_config=true
fi

backup_dir="/var/backups/bspwm-setup/netplan-$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 "$backup_dir"
cp -a -- /etc/netplan/. "$backup_dir/"
log "Backed up the current Netplan files to $backup_dir"

migration_pending=true
rm -f -- "$CONFIG_TARGET"
install -m 0600 "$CONFIG_SOURCE" "$CONFIG_TARGET"
if ! netplan generate; then
  rollback_and_die 'The NetworkManager Netplan configuration is invalid; the previous configuration was restored.'
fi

effective_config=$(netplan get 2>/dev/null || true)
if printf '%s\n' "$effective_config" | grep -Eiq 'renderer:[[:space:]]+networkd'; then
  rollback_and_die 'An existing per-interface networkd renderer overrides the new default. Resolve it manually before migrating.'
fi
printf '%s\n' "$effective_config" | grep -Eq 'renderer:[[:space:]]+NetworkManager' || {
  rollback_and_die 'Netplan did not resolve NetworkManager as the renderer; the previous configuration was restored.'
}

systemctl enable NetworkManager.service >/dev/null
cat <<'EOF'

Netplan will now switch the live network to NetworkManager for 60 seconds.
Before confirming, check that the machine still has its expected IP address
and internet access. Press Enter to keep the configuration. If connectivity is
lost, do not confirm; wait for rollback or answer no from the local console.
EOF

if ! netplan try --timeout 60; then
  warn 'NetworkManager migration was not confirmed; restoring the previous on-disk configuration.'
  rollback_and_die 'NetworkManager migration rolled back.'
fi

systemctl is-active --quiet NetworkManager.service || {
  rollback_and_die 'NetworkManager is not active after migration; restored the previous configuration.'
}
nmcli -t -f RUNNING general | grep -Fxq running || {
  rollback_and_die 'NetworkManager did not report a running state; restored the previous configuration.'
}

migration_pending=false
log 'NetworkManager now owns the Netplan-managed network devices.'
nmcli device status
log 'systemd-networkd was not removed; it remains available for explicit per-interface configurations.'
