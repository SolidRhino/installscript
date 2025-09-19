#!/usr/bin/env bash

# Uninstall and cleanup functionality

uninstall_all() {
  banner_box "${RED}" "UNINSTALL STARTED"

  run "systemctl --user disable --now cargo-update.timer docker-prune.timer lazydocker-update.timer fzf-update.timer || true"
  run "rm -f $HOME/.config/systemd/user/*.service $HOME/.config/systemd/user/*.timer"
  run "systemctl --user daemon-reload || true"

  run "cargo uninstall cargo-update || true"
  local tool
  for tool in atuin bat bottom du-dust eze fd-find helix starship yazi-fm zoxide; do
    run "cargo uninstall $tool || true"
  done

  run "rm -rf $HOME/.cargo $HOME/.rustup"

  run "sudo rm -f /usr/local/bin/{lazydocker,fzf}"
  run "rm -f $HOME/.local/bin/{lazydocker,fzf,update-lazydocker,update-fzf}"
  run "rm -rf $HOME/.config/fish $HOME/.config/starship.toml $HOME/.config/helix $HOME/.config/yazi $HOME/.config/atuin"

  if [[ "$(getent passwd "$USER" | cut -d: -f7)" = "/usr/bin/fish" ]]; then
    run "chsh -s /bin/bash"
  fi

  run "sudo systemctl stop docker || true"
  run "sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true"
  run "sudo apt autoremove -y"
  run "sudo rm -rf /var/lib/docker /etc/docker"
  run "sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg"

  run "sudo apt purge -y fish || true"
  run "sudo apt autoremove -y"
  run "sudo rm -f /etc/apt/sources.list.d/fish-shell-ubuntu-release-4-*.list"

  log_success "Uninstall complete."
  banner_uninstall
}

