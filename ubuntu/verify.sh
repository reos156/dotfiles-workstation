#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
TARGET_HOME="${HOME:-}"

usage() {
  printf 'Usage: ubuntu/verify.sh [--home PATH]\n'
}

while (($#)); do
  case "$1" in
    --home) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; TARGET_HOME="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

[[ -n "$TARGET_HOME" && "$TARGET_HOME" == /* ]] || { printf 'Verification home must be absolute.\n' >&2; exit 1; }
config_home="${XDG_CONFIG_HOME:-$TARGET_HOME/.config}"
failures=0

check_file() {
  local source="$1" destination="$2"
  if [[ ! -f "$destination" ]]; then
    printf 'MISSING  %s\n' "$destination"
    failures=$((failures + 1))
  elif cmp -s "$source" "$destination"; then
    printf 'OK       %s\n' "$destination"
  else
    printf 'CHANGED  %s\n' "$destination"
    failures=$((failures + 1))
  fi
}

check_directory() {
  local source="$1" destination="$2"
  if [[ ! -d "$destination" || -L "$destination" ]]; then
    printf 'MISSING  %s\n' "$destination"
    failures=$((failures + 1))
  elif pws_trees_equal "$source" "$destination"; then
    printf 'OK       %s\n' "$destination"
  else
    printf 'CHANGED  %s\n' "$destination"
    failures=$((failures + 1))
  fi
}

check_lua_parsing() {
  local root="$1" lua_file
  if command -v luac >/dev/null 2>&1; then
    while IFS= read -r -d '' lua_file; do
      luac -p "$lua_file" || failures=$((failures + 1))
    done < <(find "$root" -type f -name '*.lua' -print0)
    printf 'CHECKED  Lua syntax with luac\n'
  elif command -v nvim >/dev/null 2>&1; then
    while IFS= read -r -d '' lua_file; do
      nvim --headless -u NONE -i NONE --cmd "lua assert(loadfile([=[$lua_file]=]))" +qa >/dev/null 2>&1 || failures=$((failures + 1))
    done < <(find "$root" -type f -name '*.lua' -print0)
    printf 'CHECKED  Lua syntax with Neovim (plugins were not loaded)\n'
  else
    printf 'OPTIONAL Lua parser (luac/nvim not found)\n'
  fi
}

check_file "$SCRIPT_DIR/config/zsh/.zshrc" "$TARGET_HOME/.zshrc"
check_file "$SCRIPT_DIR/config/starship.toml" "$config_home/starship.toml"
check_file "$SCRIPT_DIR/config/atuin/config.toml" "$config_home/atuin/config.toml"
check_file "$SCRIPT_DIR/config/herdr/config.toml" "$config_home/herdr/config.toml"
check_directory "$SCRIPT_DIR/config/nvim" "$config_home/nvim"
check_lua_parsing "$SCRIPT_DIR/config/nvim"

for command_name in zsh git fzf nvim node brew win32yank.exe starship atuin zoxide herdr; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'FOUND    command:%s\n' "$command_name"
  else
    printf 'OPTIONAL command:%s (not found)\n' "$command_name"
  fi
done

if ((failures)); then
  printf 'Verification failed: %d managed entry or Lua parse check(s) failed.\n' "$failures" >&2
  exit 1
fi
printf 'Verification passed without network access. No files were modified.\n'
