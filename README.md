# Installscript

Enterprise-ready, modular workstation bootstrapper for Ubuntu that brings a full developer environment online in minutes. `setup.sh` orchestrates package installs, binary downloads, service configuration, update automation, post-install verification, and long-term health monitoring, all backed by structured logs, clear confirmations, and safe uninstall paths.

---

## ✨ Highlights

- **Complete environment**: Fish shell, Docker CE (engine/buildx/compose), Rust toolchain, cargo utilities, LazyDocker, fzf
- **VPN-ready**: Tailscale install + optional authentication (auth keys, tags, SSH, ephemeral, exit-node)
- **Self-healing**: Systemd timers for automatic updates (cargo, docker prune, LazyDocker/fzf updaters)
- **Safety first**: Structured confirmations, input validation, skip/dry-run/CI modes, detailed exit codes
- **Observability**: Human + JSON logs, per-step timing metrics, post-install verification, standalone health checks
- **Resilience**: Network retry logic (curl/wget), installer timeouts, graceful fallback when tools are missing
- **Lifecycle**: Self-update routine, idempotent reruns, guided uninstall/reinstall

---

## 🧱 Requirements
- Ubuntu **20.04+** (desktop or server)
- User with `sudo` rights
- Network access to GitHub (API + releases)
- Optional: Tailscale auth key, Atuin credentials

---

## 🚀 Quick Start

Clone locally (preferred):

```bash
git clone https://github.com/solidrhino/installscript.git
cd installscript
bash setup.sh
```

Or review & run via curl:

```bash
curl -fsSL https://raw.githubusercontent.com/solidrhino/installscript/main/setup.sh -o setup.sh
bash setup.sh
```

Execution streams live progress, writes `~/setup.log`, and emits structured entries to `~/setup.json.log`.

---

## 🗂️ What Gets Installed

| Category | Components |
| --- | --- |
| Shell | Fish (as default, optional), quiet greeting |
| Docker | Repo + `docker-ce`, `docker-ce-cli`, `containerd.io`, buildx, compose |
| Rust | rustup, `cargo-update`, plus curated cargo tools (atuin, bat, bottom, dust, eza, fd, helix, starship, yazi, zoxide) |
| Binaries | LazyDocker, fzf |
| Updaters | `update-lazydocker`, `update-fzf` |
| VPN | Tailscale with optional auth + configuration |
| Automation | Systemd user timers for cargo-update, docker prune, LazyDocker/fzf updaters |

---

## 🧭 Command Line Options

```bash
bash setup.sh [options]
```

| Option | Description |
| --- | --- |
| `uninstall` | Remove everything managed by this script (with confirmations) |
| `--reinstall` | Uninstall first, then reinstall (prompts before destructive actions) |
| `--skip-atuin` | Skips Atuin credential capture |
| `--skip-tailscale-auth` | Install Tailscale but skip `tailscale up` |
| `--tailscale-auth-key=KEY` | Authenticate using a specific auth key |
| `--tailscale-tags=T1,T2` | Advertise Tailscale tags (spaces stripped) |
| `--tailscale-ssh` | Enable Tailscale SSH during auth |
| `--tailscale-ephemeral` | Register node as ephemeral |
| `--tailscale-exit-node` | Advertise as exit node (reminder logged about IP forwarding) |
| `--no-fish-default` | Install Fish but keep the current login shell (no `chsh`) |
| `--dry-run` | Print actions without executing (also skips secrets) |
| `--ci` | Non-interactive CI-friendly mode (auto-confirms safe actions, skips prompts) |
| `--update-script` | Self-update `setup.sh` to the latest release and exit |
| `health` | Run passive health diagnostics and exit |
| `--help`, `-h` | Show usage information |

### Environment Variables

| Variable | Purpose |
| --- | --- |
| `ATUIN_USER`, `ATUIN_PASS` | Skip prompts by supplying credentials |
| `TAILSCALE_AUTH_KEY` | Same as CLI flag |
| `TAILSCALE_TAGS` | Same as CLI flag |
| `TAILSCALE_SSH`, `TAILSCALE_EPHEMERAL`, `TAILSCALE_EXIT_NODE` | Accept `true/false` (case-insensitive) |
| `SKIP_TAILSCALE_AUTH` | Boolean; defaults to `false` |
| `SKIP_FISH_DEFAULT` | Boolean; keep current shell instead of switching to Fish |
| `GITHUB_TOKEN` | Boost GitHub API rate limits |
| `TOTAL_STEPS_OVERRIDE` | Optional custom step count for progress bar |

Environment variables and flags can be combined; CLI options win when both provided.

---

## 🧠 Smart Behaviour

### Confirmation & Validation
- `confirm_action` respects CI/DRY-RUN and gracefully defaults in non-interactive shells
- Input validators exist for usernames, passwords, Tailscale auth keys, and tags
- Repeated invalid responses fallback to safe defaults

### Logging & Metrics
- `~/setup.log`: Human-readable stream (with colors, confirmations, errors)
- `~/setup.json.log`: Structured entries with timestamp, level, step, metadata
- Each step is timed; summary printed at completion

### Network Resilience
- `download_with_retry` handles curl/wget with exponential backoff
- `check_tool_version` enforces 5s timeout to prevent hangs
- Health checks log informational status when services or commands are missing (instead of failing)

### Self-Update
- `--update-script` downloads the latest release, validates syntax, shebang, and version match before replacing `setup.sh` (backup saved as `setup.sh.bak`)
- Automatic update checks run early in the main flow, prompting before changes

---

## 🔐 Tailscale Integration

1. Install package & repo (official apt)
2. Enable `tailscaled` service
3. Authenticate via:
   - Auth key (`--tailscale-auth-key`)
   - Interactive browser flow (`tailscale up`)
   - Skip and handle later (`--skip-tailscale-auth`)
4. Optional flags: SSH, ephemeral nodes, exit-node advertisement, tags
5. Health check warns if daemon not connected and reminds about `sudo tailscale up`
6. Exit-node reminder: logs hint to enable IP forwarding when relevant

> Tip: For CI, provide an auth key and set `SKIP_TAILSCALE_AUTH=false` to onboard automatically.

---

## 📋 Installation Flow (Default)

1. System validation & base dependencies
2. Fish shell setup
3. Rust toolchain
4. Docker engine + repo
5. Tailscale install & optional auth
6. LazyDocker + fzf binaries (+ updater scripts)
7. Cargo tool suite
8. Config deployment (dotfiles/service configs)
9. Systemd timer enablement
10. Summary + verification output

Total steps: 10 (progress bar reflects this; can be overridden).

---

## ✅ Verification & 🩺 Health

### Post-Install Verification
- Runs automatically after installation
- Checks versions for fish, rustc, cargo, docker, tailscale, LazyDocker, fzf, and cargo utilities
- Confirms updater scripts exist and respond to `--check`
- Logs failures but does not abort (you can inspect logs, rerun modules, etc.)

### Health Check (`bash setup.sh health`)
- Passive: reports missing dependencies instead of installing
- Validates systemd timers (cargo-update, docker-prune, LazyDocker/fzf updaters)
- Confirms Docker daemon is reachable
- Checks default shell vs. installed Fish
- Ensures `~/.local/bin` is on PATH
- Tests GitHub API connectivity (curl) when possible
- Reports Tailscale status and suggests `sudo tailscale up` if disconnected

---

## 🧹 Uninstall / Reinstall

- `bash setup.sh uninstall`
  - Confirms large removals, optional per-component prompts (Rust, Docker, configs)
  - Stops systemd timers, removes packages, binaries, configs
- `bash setup.sh --reinstall`
  - Prompts before uninstall, then performs fresh install
- CI-friendly (auto-confirm) when `--ci` supplied

---

## 🧪 CI & Dry Run

- `--dry-run`
  - Logs intended actions, skips downloads & secret prompts
  - Useful for reviewing changes or testing on read-only systems
- `--ci`
  - Non-interactive, auto-confirms safe actions, skips Atuin/Tailscale prompts unless credentials provided
  - Combine with env vars to fully automate provisioning

---

## 🛠️ Troubleshooting

| Issue | Resolution |
| --- | --- |
| GitHub API rate limit | Export `GITHUB_TOKEN` |
| Docker daemon unreachable | Ensure user is in `docker` group (`newgrp docker` or re-login), `sudo systemctl status docker` |
| Tailscale reports “not running” | Run `sudo tailscale up`, check auth key validity, ensure `tailscaled` active |
| Exit node not routing | Enable IP forwarding (`sysctl -w net.ipv4.ip_forward=1`) and IPv6 if needed |
| Timer status “bus unavailable” | User systemd not running; log in via graphical session or enable lingering |
| curl/wget missing in health mode | `setup.sh` health only reports; run full install to auto-install dependencies |
| Updater fails | Run indicated script with `--check` or inspect logs in `~/setup.log` |

Logs (`~/setup.log`, `~/setup.json.log`) provide granular details for diagnosing errors.

---

## 📦 Repository Layout

```
├── setup.sh            # entrypoint
├── VERSION             # current release/version marker
└── lib/
    ├── core.sh         # logging, progress, confirmations, verification, health, downloads, self-update
    ├── system.sh       # OS validation, dependency helpers
    ├── installers.sh   # module installers (Docker, Rust, Tailscale, etc.)
    ├── uninstall.sh    # guided uninstall routines
    ├── configs.sh      # dotfile/config deployment (if present)
    └── timers.sh       # systemd timer definitions (if present)
```

Modules are sourced dynamically; you can extend by adding new `lib/*.sh` components and referencing them in `setup.sh`.

---

## 🤝 Contributing

- Issues & suggestions: please open a GitHub issue
- Pull requests: welcome! Aim for small, focused changes with descriptive commits
- Style: shellcheck clean, follow existing logging/error patterns, write idempotent installers

---

## 📄 License

Unless otherwise noted, licensed under the MIT License. See `LICENSE` (if present) or accompanying repository documentation.
