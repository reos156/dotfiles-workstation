#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=0
APPROVE_PACKAGES=0
APPROVE_DOWNLOADS=0
SET_DEFAULT_SHELL=0
SKIP_PACKAGES=0
SKIP_DOWNLOADS=0
SNAPSHOT_DIR=''
MANIFEST=''
CHANGED=0

usage() {
  cat <<'USAGE'
Usage: ubuntu/install.sh [options]

  --dry-run             Print planned actions without changing the system.
  --approve-packages    Confirm human approval for apt/sudo package changes.
  --approve-downloads   Confirm human approval for recorded upstream downloads.
  --set-default-shell   Confirm human approval to run chsh for zsh.
  --skip-packages       Do not install apt packages (useful for prepared systems/tests).
  --skip-downloads      Do not clone Oh My Zsh or plugins.
  -h, --help            Show this help.
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --approve-packages) APPROVE_PACKAGES=1 ;;
    --approve-downloads) APPROVE_DOWNLOADS=1 ;;
    --set-default-shell) SET_DEFAULT_SHELL=1 ;;
    --skip-packages) SKIP_PACKAGES=1 ;;
    --skip-downloads) SKIP_DOWNLOADS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) pws_die "Unknown option: $1" ;;
  esac
  shift
done

pws_require_safe_home

preflight() {
  if [[ "${DOTFILES_WORKSTATION_TEST_MODE:-0}" == 1 ]]; then
    case "$HOME" in
      /tmp/*|"${TMPDIR:-/tmp}"/*) return ;;
      *) pws_die 'Test mode requires HOME below system temporary storage.' ;;
    esac
  fi
  [[ -r /etc/os-release ]] || pws_die 'Cannot identify Ubuntu: /etc/os-release is missing.'
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == ubuntu ]] || pws_die "Ubuntu is required (detected: ${ID:-unknown})."
  if [[ -z "${WSL_INTEROP:-}" ]] && ! grep -qi microsoft /proc/sys/kernel/osrelease /proc/version 2>/dev/null; then
    pws_die 'WSL was not detected.'
  fi
}

run() {
  if ((DRY_RUN)); then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

print_toolchain_contract() {
  cat <<'CONTRACT'
Profile: base-config
APT baseline: installs zsh, git, curl, certificates, fzf, bat, and fd-find after approval.
Recorded Zsh downloads: clones the recorded Oh My Zsh and plugin revisions after approval.
Managed configuration: installs the five documented destinations with a scoped rollback snapshot when changed.
Optional commands: configures integrations only when commands are present; binary installation is deferred.
Neovim runtime/plugins: separate optional bootstrap and health scope; not installed by base-config.
CONTRACT
  pws_log 'Non-TTY sudo may require direct authentication in an interactive Ubuntu terminal; never send a password to an agent.'
}

print_completion_guidance() {
  cat <<'GUIDANCE'
Post-install: start a fresh login shell with `exec zsh -l` or open a new Warp Ubuntu tab.
Then verify:
  printf '%s\n' "$SHELL"
  command -v zsh
  alias ls
`chsh` affects future login sessions; it does not replace the shell process already running.
Optional read-only runtime diagnostics (not run by this installer):
  ./ubuntu/check-runtime.sh
Runtime repairs require separate explicit approvals and are outside managed snapshots.
See docs/installation-runtime-remedies.md before selecting any repair.
GUIDANCE
}

install_packages() {
  local -a packages=(zsh git curl ca-certificates fzf bat fd-find)
  if ((SKIP_PACKAGES)); then
    pws_log 'Skipping apt packages.'
    return
  fi
  if ((!APPROVE_PACKAGES)); then
    pws_die 'Package installation requires --approve-packages after explicit human approval.'
  fi
  run sudo apt-get update
  run sudo apt-get install -y "${packages[@]}"
}

install_checkout() {
  local name="$1" url="$2" revision="$3" destination="$4"
  if [[ -d "$destination/.git" ]]; then
    local existing actual expected
    existing="$(git -C "$destination" remote get-url origin 2>/dev/null || true)"
    [[ "$existing" == "$url" ]] || pws_die "$destination exists with an unexpected upstream: $existing"
    actual="$(git -C "$destination" rev-parse HEAD 2>/dev/null || true)"
    expected="$(git -C "$destination" rev-parse "${revision}^{commit}" 2>/dev/null || true)"
    [[ -n "$expected" && "$actual" == "$expected" ]] || pws_die "$name exists but is not at recorded revision $revision; review it manually."
    pws_log "$name already matches recorded revision $revision."
    return
  fi
  [[ ! -e "$destination" ]] || pws_die "$destination exists but is not a managed Git checkout."
  run mkdir -p "$(dirname -- "$destination")"
  run git clone --depth 1 --branch "$revision" "$url" "$destination"
}

install_downloads() {
  local deps
  deps="$(pws_data_home)/dotfiles-workstation/deps"
  if ((SKIP_DOWNLOADS)); then
    pws_log 'Skipping upstream downloads.'
    return
  fi
  if ((!APPROVE_DOWNLOADS)); then
    pws_die 'Upstream downloads require --approve-downloads after explicit human approval.'
  fi
  install_checkout 'Oh My Zsh' 'https://github.com/ohmyzsh/ohmyzsh.git' 'master' "$deps/oh-my-zsh"
  install_checkout 'zsh-autosuggestions' 'https://github.com/zsh-users/zsh-autosuggestions.git' 'v0.7.1' "$deps/zsh-autosuggestions"
  install_checkout 'zsh-syntax-highlighting' 'https://github.com/zsh-users/zsh-syntax-highlighting.git' '0.8.0' "$deps/zsh-syntax-highlighting"
  install_checkout 'zsh-autocomplete' 'https://github.com/marlonrichert/zsh-autocomplete.git' '24.09.04' "$deps/zsh-autocomplete"
}

ensure_snapshot() {
  if [[ -n "$SNAPSHOT_DIR" ]]; then
    return
  fi
  local timestamp
  timestamp="${DOTFILES_WORKSTATION_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
  pws_validate_timestamp "$timestamp"
  SNAPSHOT_DIR="$(pws_state_root)/backups/$timestamp"
  MANIFEST="$SNAPSHOT_DIR/manifest.tsv"
  [[ ! -e "$SNAPSHOT_DIR" ]] || pws_die "Snapshot already exists: $SNAPSHOT_DIR"
  run mkdir -p "$SNAPSHOT_DIR/files"
  if ((!DRY_RUN)); then
    printf '# destination\tstate\tbackup-relative-path\tsymlink-target-base64\n' >"$MANIFEST"
  fi
}

record_snapshot_entry() {
  if ((!DRY_RUN)); then
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$MANIFEST"
  fi
}

install_managed_file() {
  local source="$1" destination="$2" label="$3"
  [[ -f "$source" ]] || pws_die "Managed source is missing: $source"
  if [[ -f "$destination" ]] && cmp -s "$source" "$destination"; then
    pws_log "Unchanged: $destination"
    return
  fi
  local state='absent' backup_rel='-' symlink_target_b64='-'
  if [[ -L "$destination" ]]; then
    local symlink_target
    readlink -n -- "$destination" >/dev/null || pws_die "Cannot read symlink target: $destination"
    symlink_target="$(readlink -n -- "$destination"; printf '.')"
    symlink_target="${symlink_target%.}"
    [[ -n "$symlink_target" ]] || pws_die "Symlink has an empty target: $destination"
    state='symlink'
    symlink_target_b64="$(printf '%s' "$symlink_target" | base64 | tr -d '\n')"
  elif [[ -f "$destination" ]]; then
    state='regular'
    backup_rel="files/$label"
  elif [[ -e "$destination" ]]; then
    pws_die "Unsupported managed destination type: $destination"
  fi
  ensure_snapshot
  if [[ "$state" == regular ]]; then
    run cp -p -- "$destination" "$SNAPSHOT_DIR/$backup_rel"
  fi
  record_snapshot_entry "$destination" "$state" "$backup_rel" "$symlink_target_b64"
  run mkdir -p "$(dirname -- "$destination")"
  if ((DRY_RUN)); then
    pws_log "Would atomically install $destination"
  else
    local temporary
    temporary="$(mktemp "$(dirname -- "$destination")/.dotfiles-workstation.XXXXXX")"
    trap '[[ -z "${temporary:-}" ]] || rm -f -- "$temporary"' RETURN
    cat -- "$source" >"$temporary"
    chmod 0644 "$temporary"
    mv -f -- "$temporary" "$destination"
    temporary=''
    trap - RETURN
  fi
  CHANGED=1
}

install_managed_directory() {
  local source="$1" destination="$2" label="$3"
  pws_reject_special_tree "$source"
  if pws_trees_equal "$source" "$destination"; then
    pws_log "Unchanged: $destination"
    return
  fi

  local state='absent-directory' backup_rel='-'
  if [[ -L "$destination" ]]; then
    pws_die "Unsupported managed directory symlink: $destination"
  elif [[ -d "$destination" ]]; then
    pws_reject_special_tree "$destination"
    state='directory'
    backup_rel="files/$label"
  elif [[ -e "$destination" ]]; then
    pws_die "Unsupported managed destination type: $destination"
  fi

  ensure_snapshot
  if [[ "$state" == directory ]]; then
    run cp -a -- "$destination" "$SNAPSHOT_DIR/$backup_rel"
  fi
  record_snapshot_entry "$destination" "$state" "$backup_rel" '-'
  run mkdir -p "$(dirname -- "$destination")"
  if ((DRY_RUN)); then
    pws_log "Would replace managed directory $destination"
  else
    local staging displaced
    staging="$(mktemp -d "$(dirname -- "$destination")/.dotfiles-workstation-dir.XXXXXX")"
    displaced=''
    trap '[[ -z "${staging:-}" ]] || rm -rf -- "$staging"; [[ -z "${displaced:-}" ]] || rm -rf -- "$displaced"' RETURN
    cp -a -- "$source/." "$staging/"
    if [[ -d "$destination" ]]; then
      displaced="$(mktemp -d "$(dirname -- "$destination")/.dotfiles-workstation-old.XXXXXX")"
      rmdir -- "$displaced"
      mv -- "$destination" "$displaced"
    fi
    if ! mv -- "$staging" "$destination"; then
      [[ -z "$displaced" ]] || mv -- "$displaced" "$destination"
      pws_die "Failed to install managed directory: $destination"
    fi
    staging=''
    if [[ -n "$displaced" ]]; then
      rm -rf -- "$displaced"
      displaced=''
    fi
    trap - RETURN
  fi
  CHANGED=1
}

validate_managed_file() {
  local source="$1" destination="$2"
  [[ -f "$source" && ! -L "$source" ]] || pws_die "Managed source is not a regular file: $source"
  if [[ -L "$destination" ]]; then
    local target
    target="$(readlink -n -- "$destination"; printf '.')"
    target="${target%.}"
    [[ -n "$target" ]] || pws_die "Symlink has an empty target: $destination"
  elif [[ -e "$destination" ]]; then
    [[ -f "$destination" ]] || pws_die "Unsupported managed destination type: $destination"
  fi
}

preflight_managed_configs() {
  local config_home
  config_home="$(pws_config_home)"
  validate_managed_file "$SCRIPT_DIR/config/zsh/.zshrc" "$HOME/.zshrc"
  validate_managed_file "$SCRIPT_DIR/config/starship.toml" "$config_home/starship.toml"
  validate_managed_file "$SCRIPT_DIR/config/atuin/config.toml" "$config_home/atuin/config.toml"
  validate_managed_file "$SCRIPT_DIR/config/herdr/config.toml" "$config_home/herdr/config.toml"
  pws_reject_special_tree "$SCRIPT_DIR/config/nvim"
  if [[ -L "$config_home/nvim" ]]; then
    pws_die "Unsupported managed directory symlink: $config_home/nvim"
  elif [[ -e "$config_home/nvim" ]]; then
    [[ -d "$config_home/nvim" ]] || pws_die "Unsupported managed destination type: $config_home/nvim"
    pws_reject_special_tree "$config_home/nvim"
  fi
}

install_configs() {
  local config_home
  config_home="$(pws_config_home)"
  install_managed_file "$SCRIPT_DIR/config/zsh/.zshrc" "$HOME/.zshrc" 'zshrc'
  install_managed_file "$SCRIPT_DIR/config/starship.toml" "$config_home/starship.toml" 'starship.toml'
  install_managed_file "$SCRIPT_DIR/config/atuin/config.toml" "$config_home/atuin/config.toml" 'atuin-config.toml'
  install_managed_file "$SCRIPT_DIR/config/herdr/config.toml" "$config_home/herdr/config.toml" 'herdr-config.toml'
  install_managed_directory "$SCRIPT_DIR/config/nvim" "$config_home/nvim" 'nvim'
}

set_default_shell() {
  if ((!SET_DEFAULT_SHELL)); then
    return 0
  fi
  command -v zsh >/dev/null 2>&1 || pws_die 'zsh is not available; cannot change the login shell.'
  local zsh_path
  zsh_path="$(command -v zsh)"
  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    pws_log "Login shell already appears to be $zsh_path."
  else
    run chsh -s "$zsh_path"
  fi
}

print_toolchain_contract
preflight
preflight_managed_configs
install_packages
install_downloads
install_configs
set_default_shell
if ((CHANGED)); then
  pws_log "Managed configuration installed. Snapshot: $SNAPSHOT_DIR"
else
  pws_log 'Managed configuration already matches; no snapshot was created.'
fi
if ((DRY_RUN)); then
  pws_log 'Dry run complete; no changes were made.'
else
  print_completion_guidance
fi
