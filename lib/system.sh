#!/usr/bin/env bash

# System validation and dependency helpers

validate_system() {
  local distro=""
  local version=""

  if command -v lsb_release >/dev/null 2>&1; then
    distro=$(lsb_release -is 2>/dev/null || true)
    version=$(lsb_release -rs 2>/dev/null || true)
  elif [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    distro="${ID:-}"
    version="${VERSION_ID:-}"
  else
    log_error_exit "Unable to determine operating system. Ensure lsb_release or /etc/os-release is available." "$E_DEPENDENCY"
  fi

  if [[ -z "$distro" ]]; then
    log_error_exit "Unable to determine operating system." "$E_UNSUPPORTED_OS"
  fi

  local distro_lower="${distro,,}"
  if [[ "$distro_lower" != "ubuntu" ]]; then
    log_error_exit "Unsupported operating system: ${distro:-unknown}. This script requires Ubuntu." "$E_UNSUPPORTED_OS"
  fi

  if [[ -z "$version" ]]; then
    log_error_exit "Unable to determine Ubuntu version." "$E_UNSUPPORTED_VERSION"
  fi

  if ! dpkg --compare-versions "$version" ge "20.04"; then
    log_error_exit "Ubuntu $version detected. Ubuntu 20.04 or higher is required." "$E_UNSUPPORTED_VERSION"
  fi
}

ensure_core_dependencies() {
  local dep
  local missing=()
  for dep in curl git wget; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep")
    fi
  done

  if (( ${#missing[@]} )); then
    log_info "Installing missing dependencies: ${missing[*]}"
    run "sudo apt update -y && sudo apt install -y ${missing[*]}"
  fi
}

report_core_dependencies() {
  local dep
  local missing=()
  for dep in curl git wget; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep")
    fi
  done

  if (( ${#missing[@]} )); then
    log_error "Missing core dependencies: ${missing[*]}"
  else
    log_success "All core dependencies (curl, git, wget) are present."
  fi
}

ensure_local_bin() {
  mkdir -p "$HOME/.local/bin"
}
