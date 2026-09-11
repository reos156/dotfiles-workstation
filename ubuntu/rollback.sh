#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  ubuntu/rollback.sh --list
  ubuntu/rollback.sh <timestamp>

A snapshot restores only the managed configuration entries listed in manifest.tsv.
Runtime data and downloaded dependency trees are never read or changed.
USAGE
}

pws_require_safe_home
BACKUP_ROOT="$(pws_state_root)/backups"

if [[ "${1:-}" == --list ]]; then
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    printf 'No snapshots found.\n'
    exit 0
  fi
  found=0
  for snapshot in "$BACKUP_ROOT"/*; do
    [[ -d "$snapshot" && -f "$snapshot/manifest.tsv" ]] || continue
    printf '%s\n' "${snapshot##*/}"
    found=1
  done
  ((found)) || printf 'No snapshots found.\n'
  exit 0
fi

[[ $# -eq 1 ]] || { usage >&2; exit 2; }
timestamp="$1"
pws_validate_timestamp "$timestamp"
snapshot="$BACKUP_ROOT/$timestamp"
manifest="$snapshot/manifest.tsv"
[[ -f "$manifest" ]] || pws_die "Snapshot manifest not found: $manifest"

allowed_destination() {
  local config_home
  config_home="$(pws_config_home)"
  case "$1" in
    "$HOME/.zshrc"|"$config_home/starship.toml"|"$config_home/atuin/config.toml"|"$config_home/herdr/config.toml"|"$config_home/nvim") return 0 ;;
    *) return 1 ;;
  esac
}

reject_unsupported_current_file_type() {
  local destination="$1"
  if [[ -e "$destination" || -L "$destination" ]]; then
    [[ -f "$destination" || -L "$destination" ]] || pws_die "Unsupported current destination type: $destination"
  fi
}

reject_unsupported_current_directory_type() {
  local destination="$1"
  if [[ -L "$destination" ]]; then
    pws_die "Unsupported current directory symlink: $destination"
  elif [[ -e "$destination" ]]; then
    [[ -d "$destination" ]] || pws_die "Unsupported current destination type: $destination"
    pws_reject_special_tree "$destination"
  fi
}

restore_file() {
  local backup="$1" destination="$2" temporary
  reject_unsupported_current_file_type "$destination"
  mkdir -p "$(dirname -- "$destination")"
  temporary="$(mktemp "$(dirname -- "$destination")/.dotfiles-workstation-restore.XXXXXX")"
  trap 'rm -f -- "${temporary:-}"' RETURN
  cat -- "$backup" >"$temporary"
  chmod --reference="$backup" "$temporary" 2>/dev/null || chmod 0644 "$temporary"
  mv -fT -- "$temporary" "$destination"
  temporary=''
  trap - RETURN
}

restore_symlink() {
  local target="$1" destination="$2" temporary_dir
  reject_unsupported_current_file_type "$destination"
  mkdir -p "$(dirname -- "$destination")"
  temporary_dir="$(mktemp -d "$(dirname -- "$destination")/.dotfiles-workstation-link.XXXXXX")"
  trap 'rm -f -- "${temporary_dir:-}/link"; rmdir -- "${temporary_dir:-}" 2>/dev/null || true' RETURN
  ln -s -- "$target" "$temporary_dir/link"
  mv -fT -- "$temporary_dir/link" "$destination"
  rmdir -- "$temporary_dir"
  temporary_dir=''
  trap - RETURN
}

restore_directory() {
  local backup="$1" destination="$2" staging displaced
  pws_reject_special_tree "$backup"
  reject_unsupported_current_directory_type "$destination"
  mkdir -p "$(dirname -- "$destination")"
  staging="$(mktemp -d "$(dirname -- "$destination")/.dotfiles-workstation-restore-dir.XXXXXX")"
  displaced=''
  trap '[[ -z "${staging:-}" ]] || rm -rf -- "$staging"; [[ -z "${displaced:-}" ]] || rm -rf -- "$displaced"' RETURN
  cp -a -- "$backup/." "$staging/"
  if [[ -d "$destination" ]]; then
    displaced="$(mktemp -d "$(dirname -- "$destination")/.dotfiles-workstation-current.XXXXXX")"
    rmdir -- "$displaced"
    mv -- "$destination" "$displaced"
  fi
  if ! mv -- "$staging" "$destination"; then
    [[ -z "$displaced" ]] || mv -- "$displaced" "$destination"
    pws_die "Failed to restore managed directory: $destination"
  fi
  staging=''
  if [[ -n "$displaced" ]]; then
    rm -rf -- "$displaced"
    displaced=''
  fi
  trap - RETURN
}

remove_managed_directory() {
  local destination="$1"
  reject_unsupported_current_directory_type "$destination"
  [[ ! -d "$destination" ]] || rm -rf -- "$destination"
}

while IFS=$'\t' read -r destination state backup_rel symlink_target_b64 extra; do
  [[ -n "$destination" && "${destination:0:1}" != '#' ]] || continue
  [[ -z "${extra:-}" ]] || pws_die "Snapshot entry has unexpected fields for $destination"
  allowed_destination "$destination" || pws_die "Snapshot contains an unmanaged destination: $destination"
  case "$state" in
    regular)
      [[ "$backup_rel" == files/* && "$backup_rel" != *'..'* && "$symlink_target_b64" == '-' ]] || pws_die "Invalid regular-file entry for $destination"
      [[ -f "$snapshot/$backup_rel" && ! -L "$snapshot/$backup_rel" ]] || pws_die "Regular-file backup payload is missing or invalid: $snapshot/$backup_rel"
      restore_file "$snapshot/$backup_rel" "$destination"
      ;;
    symlink)
      [[ "$backup_rel" == '-' && -n "$symlink_target_b64" && "$symlink_target_b64" != '-' && "$symlink_target_b64" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || pws_die "Invalid symlink entry for $destination"
      printf '%s' "$symlink_target_b64" | base64 --decode >/dev/null 2>&1 || pws_die "Cannot decode symlink target for $destination"
      decoded_target="$(printf '%s' "$symlink_target_b64" | base64 --decode; printf '.')"
      decoded_target="${decoded_target%.}"
      [[ -n "$decoded_target" ]] || pws_die "Decoded symlink target is empty for $destination"
      restore_symlink "$decoded_target" "$destination"
      ;;
    absent)
      [[ "$backup_rel" == '-' && "$symlink_target_b64" == '-' ]] || pws_die "Invalid absent-state entry for $destination"
      reject_unsupported_current_file_type "$destination"
      rm -f -- "$destination"
      ;;
    directory)
      [[ "$destination" == "$(pws_config_home)/nvim" && "$backup_rel" == 'files/nvim' && "$symlink_target_b64" == '-' ]] || pws_die "Invalid directory entry for $destination"
      [[ -d "$snapshot/$backup_rel" && ! -L "$snapshot/$backup_rel" ]] || pws_die "Directory backup payload is missing or invalid: $snapshot/$backup_rel"
      restore_directory "$snapshot/$backup_rel" "$destination"
      ;;
    absent-directory)
      [[ "$destination" == "$(pws_config_home)/nvim" && "$backup_rel" == '-' && "$symlink_target_b64" == '-' ]] || pws_die "Invalid absent-directory entry for $destination"
      remove_managed_directory "$destination"
      ;;
    *) pws_die "Unknown snapshot state '$state' for $destination" ;;
  esac
done <"$manifest"

pws_log "Restored snapshot $timestamp."
