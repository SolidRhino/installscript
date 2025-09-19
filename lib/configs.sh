#!/usr/bin/env bash

# Configuration writers for Fish, Starship, Helix, Yazi, and Atuin

setup_configs() {
  mkdir -p "$HOME/.config/fish/conf.d" "$HOME/.config/helix" "$HOME/.config/yazi/keymap" "$HOME/.config"

  write_file "$HOME/.config/fish/conf.d/path.fish" <<'EOF_FISH_PATH'
# Ensure local bins are early in PATH
if not contains -- $HOME/.local/bin $fish_user_paths
  fish_add_path -g $HOME/.local/bin
end
if not contains -- $HOME/.cargo/bin $fish_user_paths
  fish_add_path -g $HOME/.cargo/bin
end
EOF_FISH_PATH

  write_file "$HOME/.config/fish/conf.d/aliases.fish" <<'EOF_FISH_ALIAS'
# Prefer eza for ls variants when available
if type -q eza
  alias ls="eza --color=auto --group-directories-first"
  alias ll="eza -lh --icons --git"
  alias la="eza -lha --icons --git"
end

# fd alias only if APT's fdfind exists (cargo fd provides 'fd' already)
if type -q fdfind
  alias fd="fdfind"
end

alias cat="bat --style=plain --paging=never"
alias ld="lazydocker"
alias htop="btm"
EOF_FISH_ALIAS

  write_file "$HOME/.config/starship.toml" <<'EOF_STARSHIP'
add_newline = false
format = """$all"""
EOF_STARSHIP

  write_file "$HOME/.config/fish/conf.d/starship.fish" <<'EOF_STARSHIP_FISH'
starship init fish | source
EOF_STARSHIP_FISH

  write_file "$HOME/.config/fish/conf.d/zoxide.fish" <<'EOF_ZOXIDE'
zoxide init --cmd cd fish | source
EOF_ZOXIDE

  write_file "$HOME/.config/fish/conf.d/atuin.fish" <<'EOF_ATUIN'
atuin init fish | source
EOF_ATUIN

  write_file "$HOME/.config/helix/config.toml" <<'EOF_HELIX'
theme = "base16_default_dark"
[editor]
line-number = "relative"
mouse = true
cursorline = true
EOF_HELIX

  write_file "$HOME/.config/yazi/yazi.toml" <<'EOF_YAZI'
[manager]
show_hidden = true
sort_by = "name"
EOF_YAZI

  write_file "$HOME/.config/yazi/keymap/default.toml" <<'EOF_YAZI_KEYMAP'
[keymap]
j = "cursor_down"
k = "cursor_up"
h = "go_parent"
l = "enter"
EOF_YAZI_KEYMAP

  if [[ "${SKIP_ATUIN:-false}" == false && -n "${ATUIN_USER:-}" && -n "${ATUIN_PASS:-}" ]]; then
    run "atuin login -u \"$ATUIN_USER\" -p \"$ATUIN_PASS\" || true"
    run "atuin sync || true"
  fi
}
