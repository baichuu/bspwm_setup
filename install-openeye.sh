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

get_vivado_version() {
  local version=''

  if [[ -x $HOME/.local/bin/vivado-2025.2 ]]; then
    version=$("$HOME/.local/bin/vivado-2025.2" -version 2>/dev/null | sed -n '1p' || true)
  elif command -v vivado >/dev/null 2>&1; then
    version=$(vivado -version 2>/dev/null | sed -n '1p' || true)
  elif [[ -r $HOME/.config/vivado/settings64.sh ]]; then
    version=$(
      # shellcheck disable=SC1091
      source "$HOME/.config/vivado/settings64.sh"
      vivado -version 2>/dev/null | sed -n '1p'
    ) || true
  fi

  printf '%s\n' "${version:-not installed}"
}

exclude_local_artifacts() {
  local exclude_file="$install_dir/.git/info/exclude"
  local artifact

  for artifact in /environment.json /requirements.lock.txt; do
    grep -Fxq "$artifact" "$exclude_file" 2>/dev/null ||
      printf '%s\n' "$artifact" >>"$exclude_file"
  done
}

write_environment_manifest() {
  local manifest="$install_dir/environment.json"
  local python_version
  local iverilog_version
  local verilator_version
  local vivado_version

  python_version=$("$install_dir/.venv/bin/python" --version 2>&1)
  iverilog_version=$(iverilog -V 2>&1 | sed -n '1p')
  verilator_version=$(verilator --version 2>&1 | sed -n '1p')
  vivado_version=$(get_vivado_version)

  jq -n \
    --arg generated_at "$(date --iso-8601=seconds)" \
    --arg os "${PRETTY_NAME:-Ubuntu}" \
    --arg kernel "$(uname -srmo)" \
    --arg python "$python_version" \
    --arg python_executable "$install_dir/.venv/bin/python" \
    --arg simulator "$iverilog_version" \
    --arg verilator "$verilator_version" \
    --arg openeye_repository "$OPENEYE_REPOSITORY" \
    --arg openeye_commit "$(git -C "$install_dir" rev-parse HEAD)" \
    --arg vivado "$vivado_version" \
    '{
      generated_at: $generated_at,
      os: {name: $os, kernel: $kernel},
      python: {version: $python, executable: $python_executable},
      simulator: {smoke_test: $simulator, verilator: $verilator},
      openeye: {repository: $openeye_repository, commit: $openeye_commit},
      vivado: {version: $vivado},
      python_dependency_snapshot: "requirements.lock.txt"
    }' >"$manifest"
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
  jq \
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
uv pip check --python "$install_dir/.venv/bin/python"

pe_test_dir="$install_dir/test/cocotb_PE"
[[ -f $pe_test_dir/Makefile ]] || die "OpenEye PE smoke-test Makefile not found: $pe_test_dir/Makefile"
log 'Running the OpenEye PE smoke test with Icarus Verilog...'
if ! (
  cd "$pe_test_dir"
  export PATH="$install_dir/.venv/bin:$PATH"
  export VIRTUAL_ENV="$install_dir/.venv"
  export SIM=icarus
  make run
); then
  die 'OpenEye PE smoke test failed; dependency snapshot and environment manifest were not generated.'
fi
log 'OpenEye PE smoke test passed.'

exclude_local_artifacts
log 'Snapshotting the successfully tested Python environment...'
uv pip freeze --strict --exclude-editable \
  --python "$install_dir/.venv/bin/python" >"$install_dir/requirements.lock.txt"
write_environment_manifest

log "OpenEye installed at $install_dir"
log "Pinned commit: $(git -C "$install_dir" rev-parse HEAD)"
log "Environment manifest: $install_dir/environment.json"
log "Python dependency snapshot: $install_dir/requirements.lock.txt"
log "Activate with: source '$install_dir/.venv/bin/activate'"
