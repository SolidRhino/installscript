#!/usr/bin/env bash

#--------------------------------------------
# Colors & Logging Helpers
#--------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

#--------------------------------------------
# Error Codes
#--------------------------------------------
readonly E_DEPENDENCY=10
readonly E_NETWORK=11
readonly E_PERMISSION=12
readonly E_UNSUPPORTED_OS=20
readonly E_UNSUPPORTED_VERSION=21
readonly E_UNSUPPORTED_ARCH=22

log_info()    { echo -e "${YELLOW}ℹ️  $*${NC}"; }
log_success() { echo -e "${GREEN}✅ $*${NC}"; }
log_error()   { echo -e "${RED}❌ $*${NC}" >&2; }

log_error_exit() {
  local message="$1"
  local code="${2:-1}"
  trap - ERR
  log_error "${message}"
  exit "${code}"
}

#--------------------------------------------
# Progress Bar
#--------------------------------------------
TOTAL_STEPS=8
CURRENT_STEP=0

_can_tput() { command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; }

draw_progress() {
  local label="$1"
  local filled=$((CURRENT_STEP*20/TOTAL_STEPS))
  local empty=$((20-filled))
  if _can_tput; then
    tput sc
    tput cup $(($(tput lines)-1)) 0
    printf "${BLUE}[%-20s]${NC} (%d/%d) %s" \
      "$(printf '%*s' "$filled" | tr ' ' '#')$(printf '%*s' "$empty" | tr ' ' '-')" \
      "$CURRENT_STEP" "$TOTAL_STEPS" "$label"
    tput el
    tput rc
  else
    printf "${BLUE}[%-20s]${NC} (%d/%d) %s\n" \
      "$(printf '%*s' "$filled" | tr ' ' '#')$(printf '%*s' "$empty" | tr ' ' '-')" \
      "$CURRENT_STEP" "$TOTAL_STEPS" "$label"
  fi
}

progress() {
  CURRENT_STEP=$((CURRENT_STEP+1))
  draw_progress "$1"
}

#--------------------------------------------
# Banners
#--------------------------------------------
banner_box() {
  local COLOR="$1"; shift
  local MSG="$*"
  local EDGE="============================================================"
  echo -e "\n${COLOR}${EDGE}\n= $(printf '%-58s' "${MSG}")=\n${EDGE}${NC}"
}
banner_start()      { banner_box "${BLUE}"   "INSTALL STARTED"; }
banner_end()        { banner_box "${GREEN}"  "INSTALL COMPLETE"; }
banner_uninstall()  { banner_box "${RED}"    "SYSTEM CLEANED"; }
banner_reinstall()  { banner_box "${PURPLE}" "REINSTALLING"; }
banner_ci()         { banner_box "${YELLOW}" "CI/CD MODE"; }

#--------------------------------------------
# Cleanup & Sudo Helpers
#--------------------------------------------
TMPDIRS=()

core_cleanup() {
  local dir
  for dir in "${TMPDIRS[@]}"; do
    [[ -d "$dir" ]] && rm -rf "$dir"
  done
}

core_error_trap() {
  local status=$?
  local line=${BASH_LINENO[0]:-0}
  log_error_exit "Script failed on line $line with exit code $status. Check ~/setup.log for details." "$status"
}

core_sudo_keep_alive() {
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done 2>/dev/null
}

CORE_INITIALIZED=false

core_init() {
  if [[ "$CORE_INITIALIZED" == true ]]; then
    return
  fi

  trap core_error_trap ERR
  trap core_cleanup EXIT

  exec > >(tee -i ~/setup.log) 2>&1

  if sudo -v; then
    core_sudo_keep_alive &
  fi

  CORE_INITIALIZED=true
}

#--------------------------------------------
# Utility Helpers
#--------------------------------------------
run() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] $*"
  else
    eval "$@"
  fi
}

write_file() {
  local out="$1"
  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] write: $out"
    cat >/dev/null
  else
    cat >"$out"
  fi
}

