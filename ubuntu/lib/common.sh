#!/usr/bin/env bash

pws_die() {
  printf 'dotfiles-workstation: %s\n' "$*" >&2
  exit 1
}

pws_log() {
  printf '[dotfiles-workstation] %s\n' "$*"
}

pws_require_safe_home() {
  [[ -n "${HOME:-}" && "$HOME" == /* && "$HOME" != "/" ]] || pws_die 'HOME must be an absolute, non-root path.'
}

pws_config_home() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

pws_data_home() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
}

pws_state_root() {
  printf '%s\n' "$HOME/.dotfiles-workstation"
}

pws_validate_timestamp() {
  [[ "$1" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || pws_die "Invalid snapshot timestamp: $1"
}

pws_reject_special_tree() {
  local root="$1" special
  [[ -d "$root" && ! -L "$root" ]] || pws_die "Expected a real directory: $root"
  special="$(find "$root" -xdev ! -type d ! -type f ! -type l -print -quit)"
  [[ -z "$special" ]] || pws_die "Unsupported special entry in managed directory: $special"
}

pws_trees_equal() {
  local left="$1" right="$2"
  [[ -d "$left" && ! -L "$left" && -d "$right" && ! -L "$right" ]] || return 1
  diff -qr --no-dereference -- "$left" "$right" >/dev/null 2>&1
}
