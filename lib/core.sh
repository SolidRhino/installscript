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

REMOTE_REPO_BASE_URL=${REMOTE_REPO_BASE_URL:-"https://raw.githubusercontent.com/ivotrompert/installscript/main"}
REMOTE_VERSION_URL=${REMOTE_VERSION_URL:-"${REMOTE_REPO_BASE_URL}/VERSION"}
REMOTE_SCRIPT_URL=${REMOTE_SCRIPT_URL:-"${REMOTE_REPO_BASE_URL}/setup.sh"}

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

_json_escape() {
  local str="$1"
  str="${str//\\/\\\\}"
  str="${str//\"/\\\"}"
  str="${str//$'\n'/\\n}"
  str="${str//$'\r'/\\r}"
  str="${str//$'\t'/\\t}"
  str="${str//$'\f'/\\f}"
  str="${str//$'\b'/\\b}"
  printf '%s' "$str"
}


log_json() {
  local level="$1"
  local message="$2"
  local step="${3:-${CURRENT_STEP_LABEL:-}}"
  local metadata="${4:-}"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local level_json message_json payload step_json
  level_json=$(_json_escape "$level")
  message_json=$(_json_escape "$message")
  payload="{\"timestamp\":\"$timestamp\",\"level\":\"$level_json\",\"message\":\"$message_json\""
  if [[ -n "$step" ]]; then
    step_json=$(_json_escape "$step")
    payload+=",\"step\":\"$step_json\""
  fi
  if [[ -n "$metadata" ]]; then
    payload+=",\"metadata\":$metadata"
  fi
  payload+="}"
  local log_file=~/setup.json.log
  local log_dir
  log_dir=$(dirname "$log_file")
  mkdir -p "$log_dir"
  {
    if command -v flock >/dev/null 2>&1; then
      flock 200
    fi
    printf '%s\n' "$payload"
  } 200>>"$log_file"
}

#--------------------------------------------
# Progress Bar
#--------------------------------------------
TOTAL_STEPS=9
CURRENT_STEP=0
STEP_START_TIME=0
CURRENT_STEP_LABEL=""
STEP_TIMES=()

_can_tput() { command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; }

draw_progress() {
  local label="$1"
  local filled=$((CURRENT_STEP*20/TOTAL_STEPS))
  local empty=$((20-filled))
  if _can_tput; then
    tput sc
    tput cup $(($(tput lines)-1)) 0
    printf "${BLUE}[%-20s]${NC} (%d/%d) %s" \\
      "$(printf '%*s' "$filled" | tr ' ' '#')$(printf '%*s' "$empty" | tr ' ' '-')" \\
      "$CURRENT_STEP" "$TOTAL_STEPS" "$label"
    tput el
    tput rc
  else
    printf "${BLUE}[%-20s]${NC} (%d/%d) %s\n" \\
      "$(printf '%*s' "$filled" | tr ' ' '#')$(printf '%*s' "$empty" | tr ' ' '-')" \\
      "$CURRENT_STEP" "$TOTAL_STEPS" "$label"
  fi
}

_now_ns() {
  local now
  if now=$(date +%s%N 2>/dev/null) && [[ "$now" != *N* ]]; then
    printf '%s' "$now"
    return
  fi
  local seconds
  seconds=$(date +%s)
  printf '%s' "$(( seconds * 1000000000 ))"
}

format_duration() {
  local ms="$1"
  if (( ms < 1000 )); then
    printf '%d ms' "$ms"
  else
    local seconds
    seconds=$(awk "BEGIN { printf \"%.2f\", $ms/1000 }")
    printf '%s s' "$seconds"
  fi
}

_finalize_current_step() {
  local now_ns="${1:-$(_now_ns)}"
  if [[ -z "${CURRENT_STEP_LABEL:-}" || ${STEP_START_TIME:-0} -eq 0 ]]; then
    return
  fi
  local elapsed_ns=$(( now_ns - STEP_START_TIME ))
  if (( elapsed_ns < 0 )); then
    elapsed_ns=0
  fi
  local elapsed_ms=$(( elapsed_ns / 1000000 ))
  local human_duration
  human_duration=$(format_duration "$elapsed_ms")
  STEP_TIMES+=("${CURRENT_STEP_LABEL}|${elapsed_ms}")
  log_success "Step ${CURRENT_STEP}/${TOTAL_STEPS} (${CURRENT_STEP_LABEL}) completed in ${human_duration}."
  log_json "info" "Step completed" "${CURRENT_STEP_LABEL}" "{\"step_index\":${CURRENT_STEP},\"duration_ms\":${elapsed_ms}}"
  STEP_START_TIME=0
  CURRENT_STEP_LABEL=""
}

progress() {
  local label="$1"
  local now_ns=$(_now_ns)

  if [[ -n "${CURRENT_STEP_LABEL:-}" && ${STEP_START_TIME:-0} -ne 0 ]]; then
    _finalize_current_step "$now_ns"
  fi

  CURRENT_STEP=$((CURRENT_STEP+1))
  CURRENT_STEP_LABEL="$label"
  STEP_START_TIME="$now_ns"

  log_json "info" "Step started" "$label" "{\"step_index\":${CURRENT_STEP},\"total_steps\":${TOTAL_STEPS}}"
  log_info "Starting step ${CURRENT_STEP}/${TOTAL_STEPS}: ${label}"
  draw_progress "$label"
}

time_step() {
  local name="$1"
  shift
  if [[ -z "$name" || $# -eq 0 ]]; then
    log_error "time_step requires a name and command to execute."
    return 1
  fi

  local start_ns=$(_now_ns)
  local command_str=""
  if (( $# > 0 )); then
    printf -v command_str '%q ' "$@"
    command_str=${command_str% }
  fi
  local operation_json command_json
  operation_json=$(_json_escape "$name")
  command_json=$(_json_escape "$command_str")

  log_json "info" "Operation started" "${CURRENT_STEP_LABEL:-$name}" "{\"operation\":\"$operation_json\",\"command\":\"$command_json\"}"
  log_info "Running ${name}..."

  local status=0
  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] $command_str"
  else
    if "$@"; then
      status=0
    else
      status=$?
    fi
  fi

  local end_ns=$(_now_ns)
  local elapsed_ns=$(( end_ns - start_ns ))
  if (( elapsed_ns < 0 )); then
    elapsed_ns=0
  fi
  local elapsed_ms=$(( elapsed_ns / 1000000 ))
  local human_duration
  human_duration=$(format_duration "$elapsed_ms")

  local status_label
  if [[ "${DRY_RUN:-false}" == true ]]; then
    status_label="skipped"
  elif (( status == 0 )); then
    status_label="success"
  else
    status_label="error"
  fi

  if [[ $status -eq 0 ]]; then
    if [[ "$status_label" == "skipped" ]]; then
      log_info "Skipped ${name} (dry-run)."
    else
      log_success "Finished ${name} in ${human_duration}."
    fi
  else
    log_error "${name} failed after ${human_duration} (exit ${status})."
  fi

  local completion_metadata="{\"operation\":\"$operation_json\",\"duration_ms\":$elapsed_ms,\"status\":\"$status_label\"}"
  local log_level="info"
  local log_message="Operation completed"
  if (( status != 0 )); then
    log_level="error"
    log_message="Operation failed"
    completion_metadata="{\"operation\":\"$operation_json\",\"duration_ms\":$elapsed_ms,\"status\":\"$status_label\",\"exit_code\":$status}"
  fi
  log_json "$log_level" "$log_message" "${CURRENT_STEP_LABEL:-$name}" "$completion_metadata"

  return $status
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
  local path
  for path in "${TMPDIRS[@]}"; do
    [[ -n "$path" && ( -e "$path" || -L "$path" ) ]] && rm -rf "$path"
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

log_step_summary() {
  local now_ns=$(_now_ns)
  if [[ -n "${CURRENT_STEP_LABEL:-}" && ${STEP_START_TIME:-0} -ne 0 ]]; then
    _finalize_current_step "$now_ns"
  fi

  (( ${#STEP_TIMES[@]} == 0 )) && return

  log_info "Step Timing Summary:"
  local entry
  local json_array=""
  local sep=""
  for entry in "${STEP_TIMES[@]}"; do
    local name=${entry%|*}
    local duration_ms=${entry##*|}
    local human_duration
    human_duration=$(format_duration "$duration_ms")
    log_info " - ${name}: ${human_duration}"
    local name_json
    name_json=$(_json_escape "$name")
    json_array+="${sep}{\"step\":\"$name_json\",\"duration_ms\":$duration_ms}"
    sep=","
  done

  local metadata="{\"steps\":[${json_array}],\"total_steps\":${#STEP_TIMES[@]}}"
  log_json "info" "Step summary" "" "$metadata"
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

download_with_retry() {
  local url="$1"
  local dest="$2"
  local retries="${3:-3}"
  local timeout="${4:-30}"
  local -a extra_opts=()
  if (( $# > 4 )); then
    extra_opts=("${@:5}")
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] download: $url -> $dest"
    return 0
  fi

  local curl_available=false
  local wget_available=false
  command -v curl >/dev/null 2>&1 && curl_available=true
  command -v wget >/dev/null 2>&1 && wget_available=true

  if [[ "$curl_available" == false && "$wget_available" == false ]]; then
    log_error_exit "Neither curl nor wget is available to download $url." "$E_DEPENDENCY"
  fi

  local attempt delay

  if [[ "$curl_available" == true ]]; then
    for (( attempt=1; attempt<=retries; attempt++ )); do
      log_info "Downloading $url (attempt $attempt/$retries) via curl..."
      rm -f "$dest"
      if curl --fail --location --silent --show-error --connect-timeout "$timeout" --max-time "$((timeout*2))" "${extra_opts[@]}" -o "$dest" "$url"; then
        log_info "Download succeeded: $url"
        return 0
      fi
      log_error "curl attempt $attempt for $url failed."
      if (( attempt < retries )); then
        delay=$(( (2 ** (attempt-1)) * 2 ))
        log_info "Retrying in ${delay}s..."
        sleep "$delay"
      fi
    done
  fi

  if [[ "$wget_available" == true ]]; then
    if (( ${#extra_opts[@]} )); then
      log_info "Retrying download with wget for $url (curl-specific options ignored)."
    fi
    for (( attempt=1; attempt<=retries; attempt++ )); do
      log_info "Downloading $url (attempt $attempt/$retries) via wget..."
      rm -f "$dest"
      if wget --quiet --timeout="$timeout" --tries=1 -O "$dest" "$url"; then
        log_info "Download succeeded: $url"
        return 0
      fi
      log_error "wget attempt $attempt for $url failed."
      if (( attempt < retries )); then
        delay=$(( (2 ** (attempt-1)) * 2 ))
        log_info "Retrying in ${delay}s..."
        sleep "$delay"
      fi
    done
  fi

  log_error_exit "Failed to download $url after $retries attempts." "$E_NETWORK"
}

fetch_with_retry() {
  local url="$1"
  local retries="${2:-3}"
  local timeout="${3:-15}"
  local -a extra_opts=()
  if (( $# > 3 )); then
    extra_opts=("${@:4}")
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] fetch: $url"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  TMPDIRS+=("$tmp")
  download_with_retry "$url" "$tmp" "$retries" "$timeout" "${extra_opts[@]}"
  cat "$tmp"
  rm -f "$tmp"
}

_version_compare() {
  local a="$1"
  local b="$2"
  local IFS='.'
  local -a a_parts=($a)
  local -a b_parts=($b)
  local max=${#a_parts[@]}
  (( ${#b_parts[@]} > max )) && max=${#b_parts[@]}
  local i
  for (( i=0; i<max; i++ )); do
    local ai=${a_parts[i]:-0}
    local bi=${b_parts[i]:-0}
    if (( ai > bi )); then
      return 1
    elif (( ai < bi )); then
      return 2
    fi
  done
  return 0
}

get_remote_version() {
  local url="${REMOTE_VERSION_URL:-}"
  if [[ -z "$url" ]]; then
    log_error "REMOTE_VERSION_URL is not configured."
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] Fetch remote version from $url"
    printf '%s' "${SCRIPT_VERSION:-}"
    return 0
  fi

  local response
  if ! response=$(fetch_with_retry "$url" 3 15); then
    log_error "Failed to fetch remote version from $url"
    return 1
  fi
  response=$(printf '%s' "$response" | head -n1 | tr -d ' \t\r')
  printf '%s' "$response"
}

validate_script() {
  local path="$1"
  if [[ ! -s "$path" ]]; then
    log_error "Downloaded script is empty: $path"
    return 1
  fi
  local first_line
  first_line=$(head -n1 "$path")
  if [[ $first_line != '#!/usr/bin/env bash'* && $first_line != '#!/bin/bash'* ]]; then
    log_error "Downloaded script missing bash shebang."
    return 1
  fi
  if ! bash -n "$path"; then
    log_error "Syntax check failed for downloaded script."
    return 1
  fi
  return 0
}

check_script_updates() {
  local local_version="${1:-${SCRIPT_VERSION:-0}}"
  local remote_version
  if ! remote_version=$(get_remote_version); then
    return 2
  fi
  if [[ -z "$remote_version" ]]; then
    return 2
  fi
  _version_compare "$remote_version" "$local_version"
  local cmp=$?
  case "$cmp" in
    1)
      local meta_current meta_remote
      meta_current=$(_json_escape "$local_version")
      meta_remote=$(_json_escape "$remote_version")
      log_json "info" "Update available" "" "{\"current\":\"$meta_current\",\"remote\":\"$meta_remote\"}"
      printf '%s' "$remote_version"
      return 0
      ;;
    0|2)
      return 1
      ;;
    *)
      return 2
      ;;
  esac
}

update_script() {
  local script_path="$1"
  local target_version="${2:-}"
  local remote_version

  if [[ -z "$script_path" ]]; then
    log_error "Script path is required for update."
    return 1
  fi

  if [[ "$script_path" != /* ]]; then
    local script_dir
    if ! script_dir=$(cd "$(dirname "$script_path")" 2>/dev/null && pwd); then
      log_error "Unable to resolve script directory for $script_path"
      return 1
    fi
    script_path="$script_dir/$(basename "$script_path")"
  fi

  if [[ ! -f "$script_path" ]]; then
    log_error "Script not found at $script_path"
    return 1
  fi

  local local_version="${SCRIPT_VERSION:-0}"
  if [[ -z "$target_version" ]]; then
    if ! remote_version=$(get_remote_version); then
      return 1
    fi
  else
    remote_version="$target_version"
  fi

  if [[ -z "$remote_version" ]]; then
    log_error "Unable to determine remote script version."
    return 1
  fi

  _version_compare "$remote_version" "$local_version"
  local cmp=$?
  if [[ "$cmp" != 1 ]]; then
    log_info "Script already up to date (version $local_version)."
    return 0
  fi

  local meta_script meta_current meta_target meta_backup
  meta_script=$(_json_escape "$script_path")
  meta_current=$(_json_escape "$local_version")
  meta_target=$(_json_escape "$remote_version")
  log_json "info" "Script update started" "" "{\"script\":\"$meta_script\",\"current\":\"$meta_current\",\"target\":\"$meta_target\"}"
  log_info "Updating setup script from $local_version to $remote_version"

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] Would download latest script from ${REMOTE_SCRIPT_URL}"
    log_json "info" "Script update skipped (dry-run)" "" "{\"script\":\"$meta_script\",\"target\":\"$meta_target\"}"
    return 0
  fi

  local download_url="${REMOTE_SCRIPT_URL:-}"
  if [[ -z "$download_url" ]]; then
    log_error "REMOTE_SCRIPT_URL is not configured."
    return 1
  fi

  local tmp_file
  if ! tmp_file=$(mktemp); then
    log_error "Failed to create temporary file for update."
    return 1
  fi

  if ! download_with_retry "$download_url" "$tmp_file" 3 30; then
    rm -f "$tmp_file"
    log_error "Failed to download updated script."
    return 1
  fi

  if ! validate_script "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi

  local downloaded_version
  downloaded_version=$(grep -E '^SCRIPT_VERSION="[^"]+"' "$tmp_file" | head -n1 | sed -E 's/^SCRIPT_VERSION="([^"]+)".*/\1/')
  if [[ -z "$downloaded_version" ]]; then
    rm -f "$tmp_file"
    log_error "Downloaded script missing SCRIPT_VERSION declaration."
    return 1
  fi

  _version_compare "$downloaded_version" "$remote_version"
  local version_check=$?
  if (( version_check != 0 )); then
    rm -f "$tmp_file"
    log_error "Downloaded script version ($downloaded_version) does not match expected $remote_version."
    return 1
  fi

  local backup_path="${script_path}.bak"
  if ! cp "$script_path" "$backup_path"; then
    rm -f "$tmp_file"
    log_error "Failed to create backup at $backup_path"
    return 1
  fi

  if ! mv "$tmp_file" "$script_path"; then
    rm -f "$tmp_file"
    log_error "Failed to replace existing script; backup preserved at $backup_path"
    return 1
  fi

  chmod +x "$script_path"
log_success "Script updated to version $remote_version. Backup saved to $backup_path"
meta_backup=$(_json_escape "$backup_path")
  log_json "info" "Script update complete" "" "{\"script\":\"$meta_script\",\"current\":\"$meta_current\",\"updated_to\":\"$meta_target\",\"backup\":\"$meta_backup\"}"
  return 0
}

check_tool_version() {
  local name="$1"
  shift
  local cmd="$1"
  shift
  local -a run_cmd=("$cmd")
  local arg
  for arg in "$@"; do
    [[ -n "$arg" ]] && run_cmd+=("$arg")
  done

  local meta_name=$(_json_escape "$name")
  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] Skipping version check for $name"
    log_json "info" "Tool verification skipped (dry-run)" "" "{\"tool\":\"$meta_name\"}"
    return 0
  fi

  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "$name not found on PATH (expected command: $cmd)."
    log_json "error" "Tool not found" "" "{\"tool\":\"$meta_name\",\"command\":\"$(_json_escape "$cmd")\"}"
    return 1
  fi

  local output
  local exit_code
  if command -v timeout >/dev/null 2>&1; then
    output=$(timeout 5 "${run_cmd[@]}" 2>&1)
    exit_code=$?
  else
    output=$("${run_cmd[@]}" 2>&1)
    exit_code=$?
  fi

  if (( exit_code == 124 )); then
    log_error "$name check timed out after 5s."
    log_json "error" "Tool check timeout" "" "{\"tool\":\"$meta_name\",\"command\":\"$(_json_escape "$cmd")\"}"
    return 1
  fi

  if (( exit_code != 0 )); then
    log_error "$name check failed: $output"
    log_json "error" "Tool check failed" "" "{\"tool\":\"$meta_name\",\"command\":\"$(_json_escape "$cmd")\",\"output\":\"$(_json_escape "$output")\"}"
    return 1
  fi

  local first_line
  first_line=$(printf '%s' "$output" | head -n1)
  log_success "$name: $first_line"
  log_json "info" "Tool verified" "" "{\"tool\":\"$meta_name\",\"command\":\"$(_json_escape "$cmd")\",\"output\":\"$(_json_escape "$first_line")\"}"
  return 0
}

check_systemd_timer() {
  local timer="$1"
  local require="${2:-false}"
  local meta_timer=$(_json_escape "$timer")

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] Skipping timer check for $timer"
    log_json "info" "Timer check skipped (dry-run)" "" "{\"timer\":\"$meta_timer\"}"
    return 0
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    local message="systemctl command not available; timer status not checked"
    if [[ "$require" == true ]]; then
      log_error "$message"
      log_json "error" "Timer check failed" "" "{\"timer\":\"$meta_timer\",\"reason\":\"systemctl missing\"}"
      return 1
    fi
    log_info "$message"
    log_json "info" "Timer status unavailable" "" "{\"timer\":\"$meta_timer\",\"reason\":\"systemctl missing\"}"
    return 0
  fi

  local output
  output=$(systemctl --user is-active "$timer" 2>&1)
  local status=$?

  if (( status == 0 )); then
    log_success "$timer is active"
    log_json "info" "Timer active" "" "{\"timer\":\"$meta_timer\"}"
    return 0
  fi

  if [[ "$output" == *"Failed to connect to bus"* || "$output" == *"Connection refused"* ]]; then
    local message="Unable to query systemd user bus for $timer"
    if [[ "$require" == true ]]; then
      log_error "$message"
      log_json "error" "Timer check failed" "" "{\"timer\":\"$meta_timer\",\"reason\":\"bus unavailable\"}"
      return 1
    fi
    log_info "$message"
    log_json "info" "Timer status unavailable" "" "{\"timer\":\"$meta_timer\",\"reason\":\"bus unavailable\"}"
    return 0
  fi

  log_error "$timer is not active"
  log_json "error" "Timer inactive" "" "{\"timer\":\"$meta_timer\",\"status\":\"$(_json_escape "${output:-unknown}")\"}"
  return 1
}

test_docker_access() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] Skipping Docker daemon check"
    log_json "info" "Docker check skipped (dry-run)" "" "{}"
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker CLI not found on PATH."
    log_json "error" "Docker CLI missing" "" "{}"
    return 1
  fi

  local info
  if ! info=$(docker info --format '{{.ServerVersion}}' 2>/dev/null); then
    log_error "Unable to communicate with Docker daemon."
    log_json "error" "Docker daemon unreachable" "" "{}"
    return 1
  fi

  log_success "Docker daemon reachable (server version ${info})"
  log_json "info" "Docker healthy" "" "{\"serverVersion\":\"$(_json_escape "$info")\"}"
  return 0
}

check_shell_config() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] Skipping shell configuration check"
    log_json "info" "Shell check skipped (dry-run)" "" "{}"
    return 0
  fi

  local current_shell
  current_shell=$(getent passwd "$USER" | cut -d: -f7)
  local fish_path
  fish_path=$(command -v fish 2>/dev/null || true)

  if [[ -z "$fish_path" ]]; then
    log_error "Fish shell is not installed or not on PATH."
    log_json "error" "Shell mismatch" "" "{\"shell\":\"$(_json_escape "$current_shell")\",\"expected\":\"fish\"}"
    return 1
  fi

  if [[ "$current_shell" == "$fish_path" || "$current_shell" == */fish ]]; then
    log_success "Fish shell is set as the default shell."
    log_json "info" "Shell configured" "" "{\"shell\":\"$(_json_escape "$current_shell")\"}"
    return 0
  fi

  log_error "Default shell is $current_shell (expected $fish_path)."
  log_json "error" "Shell mismatch" "" "{\"shell\":\"$(_json_escape "$current_shell")\",\"expected\":\"$(_json_escape "$fish_path")\"}"
  return 1
}

verify_installation() {
  log_info "Running installation verification..."
  local -a failures=()

  check_tool_version "Fish shell" fish --version || failures+=("Fish shell")
  check_tool_version "Rust compiler" rustc --version || failures+=("rustc")
  check_tool_version "Cargo" cargo --version || failures+=("cargo")
  check_tool_version "Docker" docker --version || failures+=("docker")
  check_tool_version "LazyDocker" lazydocker --version || failures+=("lazydocker")
  check_tool_version "fzf" fzf --version || failures+=("fzf")

  local -a cargo_entries=(
    "Atuin|atuin|--version"
    "Bat|bat|--version"
    "Bottom|btm|--version"
    "Dust|dust|--version"
    "Eza|eza|--version"
    "fd|fd|--version"
    "Helix|hx|--version"
    "Starship|starship|--version"
    "Yazi|yazi|--version"
    "Zoxide|zoxide|--version"
  )

  local entry label cmd args
  for entry in "${cargo_entries[@]}"; do
    IFS='|' read -r label cmd args <<<"$entry"
    if ! check_tool_version "$label" "$cmd" "$args"; then
      failures+=("$label")
    fi
  done

  if [[ "${DRY_RUN:-false}" != true ]]; then
    local updater
    for updater in "$HOME/.local/bin/update-lazydocker" "$HOME/.local/bin/update-fzf"; do
      if [[ ! -x "$updater" ]]; then
        log_error "Updater script missing or not executable: $updater"
        failures+=("$(basename "$updater")")
        log_json "error" "Updater missing" "" "{\"script\":\"$(_json_escape "$updater")\"}"
      else
        log_success "Updater script present: $updater"
        log_json "info" "Updater present" "" "{\"script\":\"$(_json_escape "$updater")\"}"
        local check_output
        if check_output=$("$updater" --check 2>&1); then
          log_success "Updater check passed: $(basename "$updater")"
          log_json "info" "Updater check passed" "" "{\"script\":\"$(_json_escape "$updater")\"}"
        else
          log_error "Updater check failed for $(basename "$updater"): $check_output"
          log_json "error" "Updater check failed" "" "{\"script\":\"$(_json_escape "$updater")\",\"output\":\"$(_json_escape "$check_output")\"}"
          failures+=("$(basename "$updater")")
        fi
      fi
    done
  fi

  local issues_json="[]"
  if (( ${#failures[@]} > 0 )); then
    local sep=""
    issues_json="["
    local failure
    for failure in "${failures[@]}"; do
      issues_json+="$sep\"$(_json_escape "$failure")\""
      sep=","
    done
    issues_json+="]"
    log_error "Installation verification detected issues with: ${failures[*]}"
    log_json "error" "Installation verification completed" "" "{\"status\":\"failed\",\"issues\":$issues_json}"
    return 1
  fi

  log_success "Installation verification completed successfully."
  log_json "info" "Installation verification completed" "" "{\"status\":\"passed\"}"
  return 0
}

health_check() {
  log_info "Running health check..."
  local -a issues=()

  check_systemd_timer "cargo-update.timer" || issues+=("cargo-update.timer inactive")
  check_systemd_timer "docker-prune.timer" || issues+=("docker-prune.timer inactive")
  check_systemd_timer "lazydocker-update.timer" || issues+=("lazydocker-update.timer inactive")
  check_systemd_timer "fzf-update.timer" || issues+=("fzf-update.timer inactive")

  test_docker_access || issues+=("Docker daemon unavailable")
  check_shell_config || issues+=("Default shell not set to fish")

  if [[ "${DRY_RUN:-false}" != true ]]; then
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
      log_error "PATH is missing $HOME/.local/bin"
      log_json "error" "PATH missing entry" "" "{\"path\":\"$(_json_escape "$HOME/.local/bin")\"}"
      issues+=("PATH missing ~/.local/bin")
    else
      log_success "PATH includes $HOME/.local/bin"
      log_json "info" "PATH verified" "" "{}"
    fi

    if command -v curl >/dev/null 2>&1; then
      if ! curl --head --silent --fail https://api.github.com >/dev/null 2>&1; then
        log_error "Unable to reach GitHub API (network check failed)."
        log_json "error" "Network check failed" "" "{}"
        issues+=("Network connectivity to GitHub failed")
      else
        log_success "Network connectivity to GitHub confirmed."
        log_json "info" "Network check passed" "" "{}"
      fi
    else
      log_error "curl not available for network check."
      log_json "error" "Missing curl for network check" "" "{}"
      issues+=("curl not available")
    fi
  fi

  local issues_json="[]"
  if (( ${#issues[@]} > 0 )); then
    local sep=""
    issues_json="["
    local issue
    for issue in "${issues[@]}"; do
      issues_json+="$sep\"$(_json_escape "$issue")\""
      sep=","
    done
    issues_json+="]"
    log_error "Health check completed with issues: ${issues[*]}"
    log_json "error" "Health check completed" "" "{\"status\":\"failed\",\"issues\":$issues_json}"
    return 1
  fi

  log_success "Health check completed successfully."
  log_json "info" "Health check completed" "" "{\"status\":\"passed\"}"
  return 0
}

confirm_action() {
  local message="$1"
  local default_answer="${2:-y}"
  local timeout="${3:-0}"
  local context="${4:-}"
  local normalized_default
  normalized_default=$(tr '[:upper:]' '[:lower:]' <<<"${default_answer:0:1}")
  [[ "$normalized_default" == "y" ]] || normalized_default="n"

  local meta_message meta_default meta_context
  meta_message=$(_json_escape "$message")
  meta_default=$(_json_escape "$normalized_default")
  meta_context=$(_json_escape "$context")
  log_json "info" "Confirmation requested" "" "{\"message\":\"$meta_message\",\"default\":\"$meta_default\",\"context\":\"$meta_context\"}"

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] $message -> assumed yes"
    log_json "info" "Confirmation auto-approved (dry-run)" "" "{\"message\":\"$meta_message\"}"
    return 0
  fi

  if [[ "${CI_MODE:-false}" == true ]]; then
    log_info "CI mode: auto-confirming '$message'"
    log_json "info" "Confirmation auto-approved (CI)" "" "{\"message\":\"$meta_message\"}"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    log_info "Non-interactive shell: using default answer ($normalized_default) for '$message'"
    if [[ "$normalized_default" == "y" ]]; then
      log_json "info" "Confirmation auto-approved (non-interactive)" "" "{\"message\":\"$meta_message\"}"
      return 0
    fi
    log_json "info" "Confirmation auto-denied (non-interactive)" "" "{\"message\":\"$meta_message\"}"
    return 1
  fi

  local prompt_suffix
  if [[ "$normalized_default" == "y" ]]; then
    prompt_suffix="[Y/n]"
  else
    prompt_suffix="[y/N]"
  fi

  local attempts=0 response read_status
  while (( attempts < 5 )); do
    if (( timeout > 0 )); then
      read -r -t "$timeout" -p "$message $prompt_suffix " response
      read_status=$?
      if (( read_status != 0 )); then
        response=""
      fi
    else
      read -r -p "$message $prompt_suffix " response
    fi

    if [[ -z "$response" ]]; then
      response="$normalized_default"
    fi

    case "${response,,}" in
      y|yes)
        log_json "info" "Confirmation received" "" "{\"message\":\"$meta_message\",\"response\":\"yes\"}"
        return 0
        ;;
      n|no)
        log_json "info" "Confirmation denied" "" "{\"message\":\"$meta_message\",\"response\":\"no\"}"
        return 1
        ;;
      *)
        log_error "Please answer yes or no."
        ((attempts++))
        ;;
    esac
  done

  log_error "Too many invalid responses; defaulting to 'no'."
  log_json "error" "Confirmation denied after invalid attempts" "" "{\"message\":\"$meta_message\"}"
  return 1
}

validate_username() {
  local username="$1"
  VALIDATION_ERROR=""
  if [[ -z "$username" ]]; then
    VALIDATION_ERROR="Username is required."
    return 1
  fi
  if [[ ${#username} -lt 3 || ${#username} -gt 64 ]]; then
    VALIDATION_ERROR="Username must be between 3 and 64 characters."
    return 1
  fi
  if [[ ! $username =~ ^[A-Za-z0-9._-]+$ ]]; then
    VALIDATION_ERROR="Username may only contain letters, numbers, dots, underscores, or hyphens."
    return 1
  fi
  return 0
}

validate_password() {
  local password="$1"
  VALIDATION_ERROR=""
  if [[ -z "$password" ]]; then
    VALIDATION_ERROR="Password is required."
    return 1
  fi
  if [[ ${#password} -lt 8 ]]; then
    VALIDATION_ERROR="Password must be at least 8 characters."
    return 1
  fi
  return 0
}

prompt_with_validation() {
  local prompt="$1"
  local validator="$2"
  local initial_value="${3:-}"
  local attempts="${4:-5}"
  local value=""

  if [[ -n "$initial_value" ]]; then
    VALIDATION_ERROR=""
    if "$validator" "$initial_value"; then
      log_json "info" "Validation success" "" "{\"prompt\":\"$(_json_escape "$prompt")\",\"source\":\"initial\"}"
      printf '%s' "$initial_value"
      return 0
    fi
    log_error "Provided value for $prompt is invalid: ${VALIDATION_ERROR:-invalid input}."
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] Skipping prompt for: $prompt"
    printf '%s' "$initial_value"
    return 0
  fi

  if [[ "${CI_MODE:-false}" == true ]]; then
    if [[ -n "$initial_value" ]]; then
      printf '%s' "$initial_value"
      return 0
    fi
    log_error "CI mode requires providing $prompt via environment variables."
    return 1
  fi

  if [[ ! -t 0 ]]; then
    if [[ -n "$initial_value" ]]; then
      printf '%s' "$initial_value"
      return 0
    fi
    log_error "Cannot prompt for $prompt in non-interactive mode."
    return 1
  fi

  local attempt
  for (( attempt=1; attempt<=attempts; attempt++ )); do
    read -r -p "$prompt: " value
    VALIDATION_ERROR=""
    if "$validator" "$value"; then
      log_json "info" "Validation success" "" "{\"prompt\":\"$(_json_escape "$prompt")\",\"source\":\"prompt\"}"
      printf '%s' "$value"
      return 0
    fi
    log_error "${VALIDATION_ERROR:-Invalid input. Please try again.}"
  done

  log_error "Failed to capture valid input for $prompt after $attempts attempts."
  return 1
}

prompt_password_with_confirmation() {
  local prompt="$1"
  local validator="${2:-validate_password}"
  local attempts="${3:-5}"
  local pass confirm

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] Skipping password prompt for $prompt"
    printf '%s' ""
    return 0
  fi

  if [[ "${CI_MODE:-false}" == true ]]; then
    log_error "CI mode requires providing $prompt via environment variables."
    return 1
  fi

  if [[ ! -t 0 ]]; then
    log_error "Cannot prompt for $prompt in non-interactive mode."
    return 1
  fi

  local attempt
  for (( attempt=1; attempt<=attempts; attempt++ )); do
    read -s -p "$prompt: " pass
    echo
    read -s -p "Confirm $prompt: " confirm
    echo
    if [[ "$pass" != "$confirm" ]]; then
      log_error "Passwords do not match."
      continue
    fi
    if [[ -n "$validator" ]]; then
      VALIDATION_ERROR=""
      if ! "$validator" "$pass"; then
        log_error "${VALIDATION_ERROR:-Invalid password.}" 
        continue
      fi
    fi
    log_json "info" "Secret input captured" "" "{\"prompt\":\"$(_json_escape "$prompt")\"}"
    printf '%s' "$pass"
    pass=""
    confirm=""
    return 0
  done

  pass=""
  confirm=""
  log_error "Failed to capture valid password for $prompt after $attempts attempts."
  return 1
}
