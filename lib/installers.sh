#!/usr/bin/env bash

# Installer functions for toolchain setup

system_update_and_base_deps() {
  run "sudo apt update -y && sudo apt upgrade -y"
  run "sudo apt install -y build-essential pkg-config libssl-dev ca-certificates gnupg lsb-release software-properties-common unattended-upgrades"
  run "loginctl enable-linger $USER || true"
}

install_fish_shell() {
  run "sudo add-apt-repository -y ppa:fish-shell/release-4 || true"
  run "sudo apt update -y && sudo apt install -y fish"
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/fish" ]]; then
    run "chsh -s /usr/bin/fish"
  fi
  run "fish -c 'set -Ux fish_greeting \"\"' || true"
}

install_rust_toolchain() {
  if ! command -v rustc &>/dev/null; then
    run "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    if [[ "${DRY_RUN:-false}" != true && -f "$HOME/.cargo/env" ]]; then
      # shellcheck disable=SC1091
      source "$HOME/.cargo/env"
    fi
  fi
  run "cargo install cargo-update || true"
}

setup_docker() {
  if ! command -v docker &>/dev/null; then
    run "sudo install -m 0755 -d /etc/apt/keyrings"
    run "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    run 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null'
    run "sudo apt update -y && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    run "sudo usermod -aG docker $USER"
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
  local LATEST
  LATEST=$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep -Po '"tag_name": "v\K[0-9.]+' )
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
  run "curl -L https://github.com/jesseduffield/lazydocker/releases/download/v${LATEST}/lazydocker_${LATEST}_${LAZY_ARCH}.tar.gz -o $TMP/lazydocker.tar.gz"
  run "tar -xzf $TMP/lazydocker.tar.gz -C $TMP"
  run "mv $TMP/lazydocker \"$BIN\""
  run "chmod +x \"$BIN\""
  run "sudo ln -sf \"$BIN\" /usr/local/bin/lazydocker"
  log_success "LazyDocker v$LATEST ready."
}

install_fzf() {
  ensure_local_bin
  local BIN="$HOME/.local/bin/fzf"
  local LATEST
  LATEST=$(curl -s https://api.github.com/repos/junegunn/fzf/releases/latest | grep -Po '"tag_name": "v\K[0-9.]+' )
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
  run "curl -L https://github.com/junegunn/fzf/releases/download/v${LATEST}/fzf-${LATEST}-${FZF_ARCH}.tar.gz -o $TMP/fzf.tar.gz"
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
BIN="$HOME/.local/bin/lazydocker"
LATEST=$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep -Po '"tag_name": "v\K[0-9.]+' )
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
curl -L "https://github.com/jesseduffield/lazydocker/releases/download/v${LATEST}/lazydocker_${LATEST}_${LAZY_ARCH}.tar.gz" -o "$TMP/lazydocker.tar.gz"
tar -xzf "$TMP/lazydocker.tar.gz" -C "$TMP"
mv "$TMP/lazydocker" "$BIN"
chmod +x "$BIN"
EOS
  run "chmod +x $HOME/.local/bin/update-lazydocker"

  write_file "$HOME/.local/bin/update-fzf" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
BIN="$HOME/.local/bin/fzf"
LATEST=$(curl -s https://api.github.com/repos/junegunn/fzf/releases/latest | grep -Po '"tag_name": "v\K[0-9.]+' )
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
curl -L "https://github.com/junegunn/fzf/releases/download/v${LATEST}/fzf-${LATEST}-${FZF_ARCH}.tar.gz" -o "$TMP/fzf.tar.gz"
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
