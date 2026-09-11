#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"

if [[ "${1:-}" != '--approve-network' || $# -ne 1 ]]; then
  printf 'Usage: tests/bootstrap.sh --approve-network\n' >&2
  printf 'Runs Neovim bootstrap in an isolated HOME and may download plugins.\n' >&2
  exit 2
fi
command -v nvim >/dev/null 2>&1 || { printf 'Neovim is required.\n' >&2; exit 1; }
command -v git >/dev/null 2>&1 || { printf 'Git is required.\n' >&2; exit 1; }

CASE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-workstation-bootstrap.XXXXXX")"
cleanup() { rm -rf -- "$CASE_DIR"; }
trap cleanup EXIT

export HOME="$CASE_DIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$XDG_CONFIG_HOME"
cp -a -- "$ROOT/ubuntu/config/nvim" "$XDG_CONFIG_HOME/nvim"

nvim --headless "+Lazy! sync" +qa
printf 'Optional isolated Neovim bootstrap passed.\n'
