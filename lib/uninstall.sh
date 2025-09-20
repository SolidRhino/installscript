#!/usr/bin/env bash

# Uninstall and cleanup functionality

uninstall_all() {
  local auto_confirm="${1:-false}"

  if [[ "$auto_confirm" != true ]]; then
    if ! confirm_action "This will remove Docker, Rust, Fish, cargo-installed tools, and related configurations. Continue?" "n" 0 "uninstall_all"; then
      log_info "Uninstall aborted."
      return 0
    fi
  fi

  banner_box "${RED}" "UNINSTALL STARTED"

  run "systemctl --user disable --now cargo-update.timer docker-prune.timer lazydocker-update.timer fzf-update.timer || true"
  run "rm -f $HOME/.config/systemd/user/*.service $HOME/.config/systemd/user/*.timer"
  run "systemctl --user daemon-reload || true"

  local remove_rust=true
  local remove_docker=true
  local remove_configs=true

  if [[ "$auto_confirm" != true ]]; then
    if ! confirm_action "Remove Rust toolchain and all cargo-installed utilities?" "y" 0 "uninstall_rust"; then
      remove_rust=false
    fi
    if ! confirm_action "Remove Docker engine, images, containers, and apt sources?" "y" 0 "uninstall_docker"; then
      remove_docker=false
    fi
    if ! confirm_action "Remove local configuration files (Fish, Starship, Helix, Yazi, Atuin)?" "y" 0 "uninstall_configs"; then
      remove_configs=false
    fi
  fi

  if [[ "$remove_rust" == true ]]; then
    run "cargo uninstall cargo-update || true"
    local tool
    for tool in atuin bat bottom du-dust eza fd-find helix starship yazi-fm zoxide; do
      run "cargo uninstall $tool || true"
    done
    run "rm -rf $HOME/.cargo $HOME/.rustup"
  else
    log_info "Skipping Rust toolchain removal."
  fi

  if [[ "$remove_configs" == true ]]; then
    run "sudo rm -f /usr/local/bin/{lazydocker,fzf}"
    run "rm -f $HOME/.local/bin/{lazydocker,fzf,update-lazydocker,update-fzf}"
    run "rm -rf $HOME/.config/fish $HOME/.config/starship.toml $HOME/.config/helix $HOME/.config/yazi $HOME/.config/atuin"
    if [[ "$(getent passwd "$USER" | cut -d: -f7)" = "/usr/bin/fish" ]]; then
      run "chsh -s /bin/bash"
    fi
    run "sudo apt purge -y fish || true"
    run "sudo apt autoremove -y"
    run "sudo rm -f /etc/apt/sources.list.d/fish-shell-ubuntu-release-4-*.list"
  else
    log_info "Skipping configuration cleanup."
  fi

  if [[ "$remove_docker" == true ]]; then
    run "sudo systemctl stop docker || true"
    run "sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true"
    run "sudo apt autoremove -y"
    run "sudo rm -rf /var/lib/docker /etc/docker"
    run "sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg"
  else
    log_info "Skipping Docker removal."
  fi

  log_success "Uninstall complete."
  banner_uninstall
}
