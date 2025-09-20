#!/usr/bin/env bash

# Installer functions for toolchain setup

system_update_and_base_deps() {
  time_step "apt update/upgrade" bash -lc "sudo apt update -y && sudo apt upgrade -y"
  time_step "base packages" sudo apt install -y build-essential pkg-config libssl-dev ca-certificates gnupg lsb-release software-properties-common unattended-upgrades
  run "loginctl enable-linger $USER || true"
}

install_fish_shell() {
  run "sudo add-apt-repository -y ppa:fish-shell/release-4 || true"
  run "sudo apt update -y && sudo apt install -y fish"
  if [[ "${SKIP_FISH_DEFAULT:-false}" == true ]]; then
    log_info "Skipping change of default shell to fish as requested."
  else
    local current_shell
    current_shell=$(getent passwd "$USER" | cut -d: -f7)
    if [[ "$current_shell" != "/usr/bin/fish" ]]; then
      run "chsh -s /usr/bin/fish"
    fi
  fi
  run "fish -c 'set -Ux fish_greeting \"\"' || true"
}

install_rust_toolchain() {
  if ! command -v rustc &>/dev/null; then
    local rustup_installer
    local rustup_tmp=""
    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "[Dry-run] Download rustup installer from https://sh.rustup.rs"
      rustup_installer="/tmp/rustup-init.sh"
    else
      rustup_tmp=$(mktemp -d)
      TMPDIRS+=("$rustup_tmp")
      rustup_installer="$rustup_tmp/rustup-init.sh"
      download_with_retry "https://sh.rustup.rs" "$rustup_installer" 3 30 "--proto" "=https" "--tlsv1.2"
    fi
    run "sh \"$rustup_installer\" -s -- -y"
    if [[ "${DRY_RUN:-false}" != true ]]; then
      rm -f "$rustup_installer"
    fi
    if [[ "${DRY_RUN:-false}" != true && -f "$HOME/.cargo/env" ]]; then
      # shellcheck disable=SC1091
      source "$HOME/.cargo/env"
    fi
  fi
  run "cargo install cargo-update || true"
}

docker_repo_setup_commands() {
  local key_tmp="$1"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg "$key_tmp"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
}

docker_package_install() {
  sudo apt update -y
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

setup_docker() {
  if ! command -v docker &>/dev/null; then
    local docker_key_tmp
    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "[Dry-run] Download Docker GPG key"
      docker_key_tmp="/tmp/docker.gpg"
    else
      docker_key_tmp=$(mktemp)
      TMPDIRS+=("$docker_key_tmp")
      download_with_retry "https://download.docker.com/linux/ubuntu/gpg" "$docker_key_tmp" 3 30
    fi
    time_step "Docker repo setup" docker_repo_setup_commands "$docker_key_tmp"
    time_step "Docker packages" docker_package_install
    run "sudo usermod -aG docker $USER"
  fi
}

tailscale_repo_setup_commands() {
  local key_tmp="$1"
  sudo install -m 0755 -d /usr/share/keyrings
  # Write keyring; dearmor for consistent binary format
  sudo gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg "$key_tmp"
  echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
}

tailscale_package_install() {
  sudo apt update -y
  sudo apt install -y tailscale
}

build_tailscale_up_command() {
  local include_auth="$1"
  shift || true

  local -a cmd=(sudo tailscale up)

  if [[ -n "${TAILSCALE_TAGS:-}" ]]; then
    local tags="${TAILSCALE_TAGS// /}"
    [[ -n "$tags" ]] && cmd+=("--advertise-tags=${tags}")
  fi
  if [[ "${TAILSCALE_SSH:-false}" == true ]]; then
    cmd+=("--ssh")
  fi
  if [[ "${TAILSCALE_EPHEMERAL:-false}" == true ]]; then
    cmd+=("--ephemeral")
  fi
  if [[ "${TAILSCALE_EXIT_NODE:-false}" == true ]]; then
    cmd+=("--advertise-exit-node")
  fi
  if [[ "$include_auth" == true && -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    cmd+=("--authkey=${TAILSCALE_AUTH_KEY}")
  fi

  printf '%s\n' "${cmd[@]}"
}

configure_tailscale() {
  if [[ "${SKIP_TAILSCALE_AUTH:-false}" == true ]]; then
    log_info "Skipping Tailscale authentication as requested."
    return 0
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "[Dry-run] Would run 'tailscale up' to authenticate."
    return 0
  fi

  if ! command -v tailscale >/dev/null 2>&1; then
    log_error "tailscale CLI not found after installation."
    return 1
  fi

  local -a cmd
  if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    mapfile -t cmd < <(build_tailscale_up_command true)
    local key_preview="${TAILSCALE_AUTH_KEY:0:6}…"
    log_info "Authenticating Tailscale using provided auth key (${key_preview})."
    if ! "${cmd[@]}"; then
      log_error "Tailscale authentication failed when using auth key. Run 'sudo tailscale up --authkey=***' to retry manually."
      return 1
    fi
    log_success "Tailscale authentication complete."
    if [[ "${TAILSCALE_EXIT_NODE:-false}" == true ]]; then
      sysctl -n net.ipv4.ip_forward >/dev/null 2>&1 || true
      log_info "If exit node routing fails, ensure IP forwarding is enabled (e.g., net.ipv4.ip_forward=1)."
    fi
    return 0
  fi

  if [[ "${TAILSCALE_INTERACTIVE_AUTH:-false}" != true ]]; then
    log_info "Skipping Tailscale authentication. You can run 'sudo tailscale up' later."
    return 0
  fi

  mapfile -t cmd < <(build_tailscale_up_command false)
  log_info "Starting interactive Tailscale authentication (a browser window may open)."
  if ! "${cmd[@]}"; then
    log_error "Interactive Tailscale authentication failed. Run 'sudo tailscale up' to retry."
    return 1
  fi
  log_success "Tailscale authentication complete."
  if [[ "${TAILSCALE_EXIT_NODE:-false}" == true ]]; then
    sysctl -n net.ipv4.ip_forward >/dev/null 2>&1 || true
    log_info "If exit node routing fails, ensure IP forwarding is enabled (e.g., net.ipv4.ip_forward=1)."
  fi
  return 0
}

install_tailscale() {
  if command -v tailscale &>/dev/null; then
    log_success "Tailscale already installed"
  else
    local tailscale_key_tmp
    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "[Dry-run] Download Tailscale GPG key"
      tailscale_key_tmp="/tmp/tailscale.gpg"
    else
      tailscale_key_tmp=$(mktemp)
      TMPDIRS+=("$tailscale_key_tmp")
      download_with_retry "https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).noarmor.gpg" "$tailscale_key_tmp" 3 30
    fi
    time_step "Tailscale repo setup" tailscale_repo_setup_commands "$tailscale_key_tmp"
    time_step "Tailscale packages" tailscale_package_install
  fi

  time_step "Enable tailscaled" sudo systemctl enable --now tailscaled

  if [[ "${SKIP_TAILSCALE_AUTH:-false}" == true ]]; then
    log_info "Tailscale installed. Run 'sudo tailscale up' to authenticate this machine."
    return 0
  fi

  if ! configure_tailscale; then
    log_error "Tailscale configuration encountered issues. You can run 'sudo tailscale up' manually later."
  fi
}

install_lazydocker_suite() {
  install_lazydocker
  install_fzf
  install_updater_scripts
}

install_lazydocker() {
  ensure_local_bin
  local BIN="$HOME/.local/bin/lazydocker"
  local user_agent="setup-script/${SCRIPT_VERSION:-1.0}"
  local -a gh_headers=("-H" "Accept: application/vnd.github+json" "-H" "User-Agent: ${user_agent}")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    gh_headers+=("-H" "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  local release_meta
  release_meta=$(fetch_with_retry "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" 3 15 "${gh_headers[@]}") || release_meta=""
  local LATEST=""
  if [[ -n "$release_meta" ]]; then
    LATEST=$(grep -Po '"tag_name": "v\K[0-9.]+' <<<"$release_meta" || true)
  fi
  if [[ -z "$LATEST" ]]; then
    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "Dry-run: skipping LazyDocker latest version detection."
      LATEST="0.0.0"
    else
      log_error_exit "Unable to determine LazyDocker latest release." "$E_NETWORK"
    fi
  fi
  local CURRENT=""
  [[ -x "$BIN" ]] && CURRENT="$("$BIN" --version 2>/dev/null | grep -Po '[0-9.]+' || true)"
  if [[ "$CURRENT" == "$LATEST" ]]; then
    log_success "LazyDocker up-to-date (v$CURRENT)"
    return
  fi
  [[ -z "$CURRENT" ]] && log_info "Installing LazyDocker v$LATEST" || log_info "Updating LazyDocker v$CURRENT → v$LATEST"

  local ARCH=$(uname -m) LAZY_ARCH
  case "$ARCH" in
    x86_64) LAZY_ARCH="Linux_x86_64" ;;
    aarch64|arm64) LAZY_ARCH="Linux_arm64" ;;
    *) log_error_exit "Unsupported arch: $ARCH" "$E_UNSUPPORTED_ARCH" ;;
  esac
  local TMP; TMP=$(mktemp -d); TMPDIRS+=("$TMP")
  download_with_retry "https://github.com/jesseduffield/lazydocker/releases/download/v${LATEST}/lazydocker_${LATEST}_${LAZY_ARCH}.tar.gz" "$TMP/lazydocker.tar.gz" 3 60
  run "tar -xzf $TMP/lazydocker.tar.gz -C $TMP"
  run "mv $TMP/lazydocker \"$BIN\""
  run "chmod +x \"$BIN\""
  run "sudo ln -sf \"$BIN\" /usr/local/bin/lazydocker"
  log_success "LazyDocker v$LATEST ready."
}

install_fzf() {
  ensure_local_bin
  local BIN="$HOME/.local/bin/fzf"
  local user_agent="setup-script/${SCRIPT_VERSION:-1.0}"
  local -a gh_headers=("-H" "Accept: application/vnd.github+json" "-H" "User-Agent: ${user_agent}")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    gh_headers+=("-H" "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  local release_meta
  release_meta=$(fetch_with_retry "https://api.github.com/repos/junegunn/fzf/releases/latest" 3 15 "${gh_headers[@]}") || release_meta=""
  local LATEST=""
  if [[ -n "$release_meta" ]]; then
    LATEST=$(grep -Po '"tag_name": "v\K[0-9.]+' <<<"$release_meta" || true)
  fi
  if [[ -z "$LATEST" ]]; then
    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "Dry-run: skipping fzf latest version detection."
      LATEST="0.0.0"
    else
      log_error_exit "Unable to determine fzf latest release." "$E_NETWORK"
    fi
  fi
  local CURRENT=""
  [[ -x "$BIN" ]] && CURRENT="$("$BIN" --version 2>/dev/null | awk '{print $1}' || true)"
  if [[ "$CURRENT" == "$LATEST" ]]; then
    log_success "fzf up-to-date (v$CURRENT)"
    return
  fi
  [[ -z "$CURRENT" ]] && log_info "Installing fzf v$LATEST" || log_info "Updating fzf v$CURRENT → v$LATEST"

  local ARCH=$(uname -m) FZF_ARCH
  case "$ARCH" in
    x86_64) FZF_ARCH="linux_amd64" ;;
    aarch64|arm64) FZF_ARCH="linux_arm64" ;;
    *) log_error_exit "Unsupported arch: $ARCH" "$E_UNSUPPORTED_ARCH" ;;
  esac
  local TMP; TMP=$(mktemp -d); TMPDIRS+=("$TMP")
  download_with_retry "https://github.com/junegunn/fzf/releases/download/v${LATEST}/fzf-${LATEST}-${FZF_ARCH}.tar.gz" "$TMP/fzf.tar.gz" 3 60
  run "tar -xzf $TMP/fzf.tar.gz -C $TMP"
  run "mv $TMP/fzf \"$BIN\""
  run "chmod +x \"$BIN\""
  run "sudo ln -sf \"$BIN\" /usr/local/bin/fzf"
  log_success "fzf v$LATEST ready."
}

install_updater_scripts() {
  ensure_local_bin
  write_file "$HOME/.local/bin/update-lazydocker" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

download_with_retry() {
  local url="$1"
  local dest="$2"
  local retries="${3:-3}"
  local timeout="${4:-30}"
  local attempt delay
  local -a extra_opts=()
  (( $# > 4 )) && extra_opts=("${@:5}")

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
    if (( ${#extra_opts[@]} > 0 )); then
      echo "Note: wget fallback ignoring extra curl opts: ${extra_opts[*]}" >&2
    fi
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

  echo "Failed to download $url after $retries attempts" >&2
  return 1
}

fetch_with_retry() {
  local url="$1"
  local retries="${2:-3}"
  local timeout="${3:-15}"
  local -a extra_opts=()
  if (( $# > 3 )); then
    extra_opts=("${@:4}")
  fi
  local tmp
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN
  download_with_retry "$url" "$tmp" "$retries" "$timeout" "${extra_opts[@]}"
  cat "$tmp"
  trap - RETURN
  rm -f "$tmp"
}

if [[ "${1:-}" == "--check" ]]; then
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    if ! command -v tar >/dev/null 2>&1; then
      echo "update-lazydocker: required command 'tar' not found" >&2
      exit 1
    fi
    echo "update-lazydocker: prerequisites satisfied"
    exit 0
  else
    echo "update-lazydocker: missing curl or wget" >&2
    exit 1
  fi
fi

BIN="$HOME/.local/bin/lazydocker"
HEADERS=("-H" "Accept: application/vnd.github+json" "-H" "User-Agent: setup-script/${SCRIPT_VERSION:-1.0}")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  HEADERS+=("-H" "Authorization: Bearer ${GITHUB_TOKEN}")
fi
LATEST=$(fetch_with_retry "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" 3 15 "${HEADERS[@]}" | grep -Po '"tag_name": "v\K[0-9.]+' || true)
[[ -z "$LATEST" ]] && { echo "Unable to determine latest LazyDocker release" >&2; exit 1; }
CURRENT=""
[[ -x "$BIN" ]] && CURRENT="$("$BIN" --version 2>/dev/null | grep -Po '[0-9.]+' || true)"
[[ "$CURRENT" == "$LATEST" ]] && exit 0
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) LAZY_ARCH="Linux_x86_64" ;;
  aarch64|arm64) LAZY_ARCH="Linux_arm64" ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
download_with_retry "https://github.com/jesseduffield/lazydocker/releases/download/v${LATEST}/lazydocker_${LATEST}_${LAZY_ARCH}.tar.gz" "$TMP/lazydocker.tar.gz" 3 60
tar -xzf "$TMP/lazydocker.tar.gz" -C "$TMP"
mv "$TMP/lazydocker" "$BIN"
chmod +x "$BIN"
EOS
  run "chmod +x $HOME/.local/bin/update-lazydocker"

  write_file "$HOME/.local/bin/update-fzf" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

download_with_retry() {
  local url="$1"
  local dest="$2"
  local retries="${3:-3}"
  local timeout="${4:-30}"
  local attempt delay
  local -a extra_opts=()
  (( $# > 4 )) && extra_opts=("${@:5}")

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
    if (( ${#extra_opts[@]} > 0 )); then
      echo "Note: wget fallback ignoring extra curl opts: ${extra_opts[*]}" >&2
    fi
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

  echo "Failed to download $url after $retries attempts" >&2
  return 1
}

fetch_with_retry() {
  local url="$1"
  local retries="${2:-3}"
  local timeout="${3:-15}"
  local -a extra_opts=()
  if (( $# > 3 )); then
    extra_opts=("${@:4}")
  fi
  local tmp
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN
  download_with_retry "$url" "$tmp" "$retries" "$timeout" "${extra_opts[@]}"
  cat "$tmp"
  trap - RETURN
  rm -f "$tmp"
}

if [[ "${1:-}" == "--check" ]]; then
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    if ! command -v tar >/dev/null 2>&1; then
      echo "update-fzf: required command 'tar' not found" >&2
      exit 1
    fi
    echo "update-fzf: prerequisites satisfied"
    exit 0
  else
    echo "update-fzf: missing curl or wget" >&2
    exit 1
  fi
fi

BIN="$HOME/.local/bin/fzf"
HEADERS=("-H" "Accept: application/vnd.github+json" "-H" "User-Agent: setup-script/${SCRIPT_VERSION:-1.0}")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  HEADERS+=("-H" "Authorization: Bearer ${GITHUB_TOKEN}")
fi
LATEST=$(fetch_with_retry "https://api.github.com/repos/junegunn/fzf/releases/latest" 3 15 "${HEADERS[@]}" | grep -Po '"tag_name": "v\K[0-9.]+' || true)
[[ -z "$LATEST" ]] && { echo "Unable to determine latest fzf release" >&2; exit 1; }
CURRENT=""
[[ -x "$BIN" ]] && CURRENT="$("$BIN" --version 2>/dev/null | awk '{print $1}' || true)"
[[ "$CURRENT" == "$LATEST" ]] && exit 0
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) FZF_ARCH="linux_amd64" ;;
  aarch64|arm64) FZF_ARCH="linux_arm64" ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
download_with_retry "https://github.com/junegunn/fzf/releases/download/v${LATEST}/fzf-${LATEST}-${FZF_ARCH}.tar.gz" "$TMP/fzf.tar.gz" 3 60
tar -xzf "$TMP/fzf.tar.gz" -C "$TMP"
mv "$TMP/fzf" "$BIN"
chmod +x "$BIN"
EOS
  run "chmod +x $HOME/.local/bin/update-fzf"
}

install_cargo_tools() {
  local tool
  local -a TOOLS=(atuin bat bottom du-dust eza fd-find helix starship yazi-fm zoxide)
  for tool in "${TOOLS[@]}"; do
    run "cargo install --locked $tool || true"
  done

  run "sudo mkdir -p /usr/local/bin"
  local bin
  for bin in "$HOME/.cargo/bin/"* "$HOME/.local/bin/"*; do
    [[ -f "$bin" && -x "$bin" ]] && run "sudo ln -sf \"$bin\" /usr/local/bin/$(basename "$bin")"
  done
}
