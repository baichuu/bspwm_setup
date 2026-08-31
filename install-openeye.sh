#!/usr/bin/env bash

set -Eeuo pipefail

readonly OPENEYE_REPOSITORY='https://github.com/Learning-Chips-Lab/OpenEye.git'
readonly OPENEYE_COMMIT='fe2f5ed169d4e4bf1d2e960601588e7c5d71c4e3'
install_dir="$HOME/Projects/OpenEye"

log() {
  printf '\033[1;32m[install-openeye.sh]\033[0m %s\n' "$*"
}

die() {
  printf '\033[1;31m[install-openeye.sh]\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: ./install-openeye.sh [--dir PATH]

Install the OpenEye RTL/Python environment at the commit pinned by the
DominoSearch FPGA plan. Python environments and dependencies are managed by uv.
EOF
}

while (($#)); do
  case $1 in
  --dir)
    (($# >= 2)) || die '--dir requires a path.'
    install_dir=$2
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

[[ $EUID -ne 0 ]] || die 'Run this script as your regular user, without sudo.'

[[ -r /etc/os-release ]] || die 'Cannot detect the operating system.'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || die "Ubuntu is required (detected: ${ID:-unknown})."

install_dir=$(realpath -m -- "$install_dir")

log 'Installing RTL simulation and source-build dependencies...'
sudo -v
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  gtkwave \
  iverilog \
  make \
  pkg-config \
  python3 \
  python3-dev \
  verilator

if ! command -v uv >/dev/null 2>&1; then
  log 'Installing uv with the official Astral installer...'
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v uv >/dev/null 2>&1 || die 'uv installation failed.'

if [[ -e $install_dir ]]; then
  [[ -d $install_dir/.git ]] || die "Path exists and is not an OpenEye Git checkout: $install_dir"
  current_remote=$(git -C "$install_dir" remote get-url origin 2>/dev/null || true)
  [[ $current_remote == "$OPENEYE_REPOSITORY" ]] ||
    die "Existing repository has a different origin: $current_remote"
  [[ -z $(git -C "$install_dir" status --short) ]] ||
    die "Existing OpenEye worktree has changes; preserving it without modification: $install_dir"
  [[ $(git -C "$install_dir" rev-parse HEAD) == "$OPENEYE_COMMIT" ]] ||
    die "Existing OpenEye checkout is at another commit; preserving it: $install_dir"
else
  install -d -m 0755 "$(dirname -- "$install_dir")"
  git clone "$OPENEYE_REPOSITORY" "$install_dir"
  git -C "$install_dir" checkout --detach "$OPENEYE_COMMIT"
fi

log 'Creating the OpenEye Python environment with uv...'
uv venv --python python3 "$install_dir/.venv"
uv pip install --python "$install_dir/.venv/bin/python" \
  -r "$install_dir/requirements.txt"
uv pip install --python "$install_dir/.venv/bin/python" -e "$install_dir"

"$install_dir/.venv/bin/python" -c 'import open_eye'
iverilog -V | sed -n '1p'

log "OpenEye installed at $install_dir"
log "Pinned commit: $(git -C "$install_dir" rev-parse HEAD)"
log "Activate with: source '$install_dir/.venv/bin/activate'"
log "First smoke test: cd '$install_dir/test/cocotb_PE' && make run"
