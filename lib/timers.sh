#!/usr/bin/env bash

# Systemd timer setup

setup_systemd_timers() {
  mkdir -p "$HOME/.config/systemd/user"

  write_file "$HOME/.config/systemd/user/cargo-update.service" <<'EOF_CARGO_SERVICE'
[Unit]
Description=Update all cargo-installed binaries
[Service]
Type=oneshot
ExecStart=%h/.cargo/bin/cargo install-update -a
EOF_CARGO_SERVICE

  write_file "$HOME/.config/systemd/user/cargo-update.timer" <<'EOF_CARGO_TIMER'
[Unit]
Description=Run cargo-update weekly
[Timer]
OnCalendar=weekly
Persistent=true
[Install]
WantedBy=timers.target
EOF_CARGO_TIMER

  write_file "$HOME/.config/systemd/user/docker-prune.service" <<'EOF_DOCKER_SERVICE'
[Unit]
Description=Auto-remove unused Docker containers, images, and volumes
[Service]
Type=oneshot
ExecStart=/usr/bin/docker system prune -af --volumes
EOF_DOCKER_SERVICE

  write_file "$HOME/.config/systemd/user/docker-prune.timer" <<'EOF_DOCKER_TIMER'
[Unit]
Description=Run docker system prune weekly
[Timer]
OnCalendar=weekly
Persistent=true
[Install]
WantedBy=timers.target
EOF_DOCKER_TIMER

  write_file "$HOME/.config/systemd/user/lazydocker-update.service" <<'EOF_LAZY_SERVICE'
[Unit]
Description=Update LazyDocker to latest release if newer is available
[Service]
Type=oneshot
ExecStart=%h/.local/bin/update-lazydocker
EOF_LAZY_SERVICE

  write_file "$HOME/.config/systemd/user/lazydocker-update.timer" <<'EOF_LAZY_TIMER'
[Unit]
Description=Run LazyDocker updater weekly
[Timer]
OnCalendar=weekly
Persistent=true
[Install]
WantedBy=timers.target
EOF_LAZY_TIMER

  write_file "$HOME/.config/systemd/user/fzf-update.service" <<'EOF_FZF_SERVICE'
[Unit]
Description=Update fzf to latest release if newer is available
[Service]
Type=oneshot
ExecStart=%h/.local/bin/update-fzf
EOF_FZF_SERVICE

  write_file "$HOME/.config/systemd/user/fzf-update.timer" <<'EOF_FZF_TIMER'
[Unit]
Description=Run fzf updater weekly
[Timer]
OnCalendar=weekly
Persistent=true
[Install]
WantedBy=timers.target
EOF_FZF_TIMER

  run "systemctl --user daemon-reload"
  run "systemctl --user enable --now cargo-update.timer docker-prune.timer lazydocker-update.timer fzf-update.timer"
}

