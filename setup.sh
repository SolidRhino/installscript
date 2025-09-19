#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="1.0.0"
DEFAULT_MODULE_BASE_URL="https://raw.githubusercontent.com/ivotrompert/installscript/main/lib"
MODULE_BASE_URL="${SETUP_MODULE_BASE_URL:-$DEFAULT_MODULE_BASE_URL}"
MODULE_CACHE_DIR="$HOME/.cache/setup-script/${SCRIPT_VERSION}"
MODULES=(core system installers configs timers uninstall)

fatal() {
  echo "setup.sh: $*" >&2
  exit 1
}

module_download() {
  local url="$1"
  local dest="$2"
  local retries="${3:-3}"
  local timeout="${4:-30}"
  local -a extra_opts=()
  if (( $# > 4 )); then
    extra_opts=("${@:5}")
  fi

  local attempt delay

  if command -v curl >/dev/null 2>&1; then
    for (( attempt=1; attempt<=retries; attempt++ )); do
      rm -f "$dest"
      if curl --fail --location --silent --show-error --connect-timeout "$timeout" --max-time "$((timeout*2))" "${extra_opts[@]}" -o "$dest" "$url"; then
        return 0
      fi
      if (( attempt < retries )); then
        delay=$(( (2 ** (attempt-1)) * 2 ))
        sleep "$delay"
      fi
    done
  fi

  if command -v wget >/dev/null 2>&1; then
    for (( attempt=1; attempt<=retries; attempt++ )); do
      rm -f "$dest"
      if wget --quiet --timeout="$timeout" --tries=1 -O "$dest" "$url"; then
        return 0
      fi
      if (( attempt < retries )); then
        delay=$(( (2 ** (attempt-1)) * 2 ))
        sleep "$delay"
      fi
    done
  fi

  return 1
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

  if module_download "$url" "$cached" 3 30; then
    echo "$cached"
    return 0
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
UPDATE_CHECK_ENABLED=true
MODE_UNINSTALL=0
MODE_HEALTH=0

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
  health          Run system health check and exit
  --update-script Update this script to the latest version and exit
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
    health) MODE_HEALTH=1 ;;
    --update-script)
      if [[ -z "${SCRIPT_SOURCE:-}" ]]; then
        log_error "Unable to determine script path for self-update."
        exit 1
      fi
      if update_script "$SCRIPT_SOURCE"; then
        log_success "Update routine finished. Please rerun the script."
        exit 0
      else
        log_error "Self-update failed."
        exit 1
      fi
      ;;
    --help|-h) show_help 0 ;;
    *) log_error "Unknown argument: $arg"; show_help 2 ;;
  esac
done

if [[ "$DRY_RUN" == true ]]; then
  SKIP_ATUIN=true
fi

if [[ "$MODE_HEALTH" -eq 1 ]]; then
  validate_system
  report_core_dependencies
  if health_check; then
    exit 0
  else
    exit 1
  fi
fi

if [[ "$MODE_UNINSTALL" -eq 1 ]]; then
  uninstall_all
  exit 0
fi

if [[ "$DO_REINSTALL" == true ]]; then
  if confirm_action "Reinstall will remove installed components before reinstalling them. Continue?" "n" 0 "reinstall"; then
    uninstall_all true
  else
    log_info "Reinstall cancelled by user."
    exit 0
  fi
  banner_reinstall
  log_info "Continuing with fresh install..."
fi

if [[ "$CI_MODE" == true ]]; then
  banner_ci
  log_info "Running in CI/CD mode (non-interactive)."
  UPDATE_CHECK_ENABLED=false
fi

validate_system
ensure_core_dependencies

if [[ "$UPDATE_CHECK_ENABLED" == true ]]; then
  remote_version=""
  if remote_version=$(check_script_updates "$SCRIPT_VERSION"); then
    update_status=0
  else
    update_status=$?
    remote_version=""
  fi
  if (( update_status == 0 )); then
    log_info "New setup script version available: $SCRIPT_VERSION → $remote_version"
    if [[ "$CI_MODE" == true ]]; then
      log_info "Skipping self-update in CI mode."
    elif [[ -n "${SCRIPT_SOURCE:-}" && -t 0 ]]; then
      read -r -p "Update to version $remote_version now? [y/N]: " reply
      if [[ "$reply" =~ ^[Yy]$ ]]; then
        if update_script "$SCRIPT_SOURCE" "$remote_version"; then
          log_success "Script updated to version $remote_version. Please rerun setup."
          exit 0
        else
          log_error "Script update failed; continuing with current version."
        fi
      fi
    else
      log_info "Run with --update-script to upgrade."
    fi
  elif (( update_status == 2 )); then
    log_error "Unable to check for script updates."
  fi
fi

banner_start
log_info "setup.sh version ${SCRIPT_VERSION}"
log_info "Starting setup…"

: "${ATUIN_USER:=}"
: "${ATUIN_PASS:=}"
if [[ "$SKIP_ATUIN" == false ]]; then
  if [[ -n "$ATUIN_USER" ]]; then
    VALIDATION_ERROR=""
    if ! validate_username "$ATUIN_USER"; then
      log_error "Provided Atuin username is invalid: ${VALIDATION_ERROR}"
      ATUIN_USER=""
    fi
  fi

  if [[ -z "$ATUIN_USER" ]]; then
    if [[ "$CI_MODE" == true ]]; then
      log_info "CI mode without Atuin username; skipping Atuin setup."
      SKIP_ATUIN=true
    else
      log_info "Atuin sync requires a valid username (3-64 chars, alphanumeric plus . _ -)."
      if ! ATUIN_USER=$(prompt_with_validation "Atuin username" validate_username "" 5); then
        log_error "Unable to capture a valid Atuin username. Skipping Atuin setup."
        SKIP_ATUIN=true
      fi
    fi
  fi

  if [[ "$SKIP_ATUIN" == false && -n "$ATUIN_PASS" ]]; then
    VALIDATION_ERROR=""
    if ! validate_password "$ATUIN_PASS"; then
      log_error "Provided Atuin password is invalid: ${VALIDATION_ERROR}"
      ATUIN_PASS=""
    fi
  fi

  if [[ "$SKIP_ATUIN" == false && -z "$ATUIN_PASS" ]]; then
    if [[ "$CI_MODE" == true ]]; then
      log_info "CI mode without Atuin password; skipping Atuin setup."
      SKIP_ATUIN=true
    else
      log_info "Enter your Atuin password (minimum 8 characters)."
      if ! ATUIN_PASS=$(prompt_password_with_confirmation "Atuin password" validate_password 5); then
        log_error "Unable to capture a valid Atuin password. Skipping Atuin setup."
        SKIP_ATUIN=true
      fi
    fi
  fi

  if [[ "$SKIP_ATUIN" == false ]]; then
    if ! confirm_action "Proceed with Atuin login for user '$ATUIN_USER'?" "y" 0 "atuin_credentials"; then
      log_info "Skipping Atuin setup at user request."
      SKIP_ATUIN=true
      ATUIN_USER=""
      ATUIN_PASS=""
    fi
  fi
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
if verify_installation; then
  log_success "Installation verification passed."
else
  log_error "Installation verification reported issues. Review the log for details."
fi
log_info "Run ./setup.sh health periodically to verify system health."

log_step_summary
banner_end
