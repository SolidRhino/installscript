#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="1.0.0"
DEFAULT_MODULE_BASE_URL="https://raw.githubusercontent.com/solidrhino/installscript/main/lib"
MODULE_BASE_URL="${SETUP_MODULE_BASE_URL:-$DEFAULT_MODULE_BASE_URL}"
MODULE_CACHE_DIR="$HOME/.cache/setup-script/${SCRIPT_VERSION}"
MODULES=(core system installers configs timers uninstall)

fatal() {
  echo "setup.sh: $*" >&2
  exit 1
}

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
  SCRIPT_DIR=""
fi

locate_module() {
  local module="$1"
  local local_path

  if [[ -n "$SCRIPT_DIR" ]]; then
    local_path="$SCRIPT_DIR/lib/${module}.sh"
    if [[ -f "$local_path" ]]; then
      echo "$local_path"
      return 0
    fi
  fi

  local cached="$MODULE_CACHE_DIR/${module}.sh"
  if [[ -f "$cached" ]]; then
    echo "$cached"
    return 0
  fi

  mkdir -p "$MODULE_CACHE_DIR"
  local url="${MODULE_BASE_URL%/}/${module}.sh"

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$url" -o "$cached"; then
      echo "$cached"
      return 0
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -q -O "$cached" "$url"; then
      echo "$cached"
      return 0
    fi
  else
    fatal "Neither curl nor wget available to download module '$module'."
  fi

  fatal "Failed to download module '$module' from $url"
}

load_modules() {
  local module module_path
  for module in "${MODULES[@]}"; do
    module_path="$(locate_module "$module")" || fatal "Could not locate module '$module'"
    # shellcheck source=/dev/null
    source "$module_path"
  done
}

load_modules
core_init

SKIP_ATUIN=false
DO_REINSTALL=false
DRY_RUN=false
CI_MODE=false
MODE_UNINSTALL=0

show_help() {
  local code=${1:-0}
  cat <<'EOF_HELP'
Usage: $0 [OPTION]

Options:
  uninstall       Remove everything installed by this script and reset system
  --skip-atuin    Skip Atuin login (no prompt, no env vars used)
  --reinstall     Uninstall everything first, then reinstall
  --dry-run       Show what would be done, but make no changes
  --ci            Run in CI/CD mode (non-interactive, skip Atuin)
  --help          Show this help message

Environment variables:
  ATUIN_USER      Atuin username (used if set, skips prompt)
  ATUIN_PASS      Atuin password (used if set, skips prompt)
EOF_HELP
  exit "$code"
}

for arg in "$@"; do
  case "$arg" in
    uninstall) MODE_UNINSTALL=1 ;;
    --skip-atuin) SKIP_ATUIN=true ;;
    --reinstall) DO_REINSTALL=true ;;
    --dry-run) DRY_RUN=true ;;
    --ci) CI_MODE=true; SKIP_ATUIN=true ;;
    --help|-h) show_help 0 ;;
    *) log_error "Unknown argument: $arg"; show_help 2 ;;
  esac
done

if [[ "$MODE_UNINSTALL" -eq 1 ]]; then
  uninstall_all
  exit 0
fi

if [[ "$DO_REINSTALL" == true ]]; then
  uninstall_all
  banner_reinstall
  log_info "Continuing with fresh install..."
fi

if [[ "$CI_MODE" == true ]]; then
  banner_ci
  log_info "Running in CI/CD mode (non-interactive)."
fi

validate_system
ensure_core_dependencies

banner_start
log_info "Starting setup…"

: "${ATUIN_USER:=}"
: "${ATUIN_PASS:=}"
if [[ "$SKIP_ATUIN" == false && ( -z "${ATUIN_USER}" || -z "${ATUIN_PASS}" ) && "$CI_MODE" == false ]]; then
  read -p "Atuin username: " ATUIN_USER
  read -s -p "Atuin password: " ATUIN_PASS
  echo
fi

progress "System Update & Base Dependencies"
system_update_and_base_deps

progress "Fish Shell"
install_fish_shell

progress "Rust"
install_rust_toolchain

progress "Docker"
setup_docker

progress "LazyDocker & fzf"
install_lazydocker_suite

progress "Cargo Tools"
install_cargo_tools

progress "Configs"
setup_configs

progress "Systemd Timers"
setup_systemd_timers

progress "Summary"
log_success "Installation complete. Versions installed:"
fish --version || true
rustc --version || true
docker --version || true
lazydocker --version || true
fzf --version || true
atuin --version || true
btm --version || true

banner_end
