#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

RUNTIME_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
RUNTIME_UBUNTU_DIR="$(cd -- "$RUNTIME_LIB_DIR/.." && pwd -P)"
RUNTIME_LOCK="${DOTFILES_RUNTIME_LOCK:-$RUNTIME_UBUNTU_DIR/runtime.lock.tsv}"
RUNTIME_LUA="$RUNTIME_UBUNTU_DIR/runtime-bootstrap.lua"
CONFIG_SOURCE="$RUNTIME_UBUNTU_DIR/config/nvim/lazy-lock.json"
CONFIG_DEPLOYED="${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lazy-lock.json"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
RUNTIME_ROOT="$DATA_HOME/dotfiles-workstation/runtime"
NVIM_DATA="$DATA_HOME/nvim"
LAZY_ROOT="$NVIM_DATA/lazy/lazy.nvim"
TREE_ROOT="$RUNTIME_ROOT/tree-sitter/0.27.0"
TREE_URL='https://github.com/tree-sitter/tree-sitter/releases/download/v0.27.0/tree-sitter-linux-x64.gz'
TREE_SHA='20a1f39ec1c45f2211492dcb8881c802b643b554bb196869a29ac3778277fa77'
if [[ "${DOTFILES_WORKSTATION_TEST_MODE:-0}" == 1 && -n "${RUNTIME_TEST_TREE_GZIP:-}" ]]; then
  TREE_SHA="$(sha256sum "$RUNTIME_TEST_TREE_GZIP" | awk '{print $1}')"
fi

runtime_die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
runtime_log() { printf '%s\n' "$*"; }

validate_platform() {
  local os_id os_version architecture
  if [[ "${DOTFILES_WORKSTATION_TEST_MODE:-0}" == 1 ]]; then
    os_id="${DOTFILES_WORKSTATION_TEST_OS_ID:-ubuntu}"
    os_version="${DOTFILES_WORKSTATION_TEST_OS_VERSION:-26.04}"
    architecture="${DOTFILES_WORKSTATION_TEST_ARCH:-x86_64}"
  else
    [[ -r /etc/os-release ]] || runtime_die 'Cannot identify the runtime-bootstrap platform.'
    # shellcheck disable=SC1091
    source /etc/os-release
    os_id="${ID:-}"
    os_version="${VERSION_ID:-}"
    architecture="$(uname -m)"
  fi
  [[ "$os_id" == ubuntu && "$os_version" == 26.04 && "$architecture" == x86_64 ]] ||
    runtime_die "Runtime bootstrap supports Ubuntu 26.04 Linux x86_64 only (detected: ${os_id:-unknown} ${os_version:-unknown} ${architecture:-unknown})."
}

[[ -f "$RUNTIME_LOCK" && ! -L "$RUNTIME_LOCK" ]] || runtime_die "Runtime lock is missing or unsafe: $RUNTIME_LOCK"
[[ -f "$RUNTIME_LUA" && ! -L "$RUNTIME_LUA" ]] || runtime_die "Runtime bootstrap Lua is missing or unsafe: $RUNTIME_LUA"
[[ -f "$CONFIG_SOURCE" && ! -L "$CONFIG_SOURCE" ]] || runtime_die 'Repository Neovim lockfile is required.'

LAZY_COMMIT="$(python3 - "$CONFIG_SOURCE" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    print(json.load(source)["lazy.nvim"]["commit"])
PY
)"
[[ "$LAZY_COMMIT" =~ ^[0-9a-f]{40}$ ]] || runtime_die 'Repository lazy.nvim lock entry is invalid.'

if [[ "${1:-}" == --dry-run && $# -eq 1 ]]; then
  runtime_log "Pinned Neovim runtime bootstrap: lazy.nvim $LAZY_COMMIT; 11 Mason package versions from the official registry; tree-sitter CLI 0.27.0 and 25 parsers."
  runtime_log 'Dry run: no network, plugin bootstrap, package install, parser compilation, or runtime repair was started.'
  exit 0
fi
[[ "${1:-}" == --approve-runtime-bootstrap && $# -eq 1 ]] ||
  runtime_die 'Runtime mutation requires exactly --approve-runtime-bootstrap after explicit human approval.'

validate_platform
[[ -f "$CONFIG_DEPLOYED" && ! -L "$CONFIG_DEPLOYED" ]] || runtime_die 'Deployed Neovim lockfile is required.'
cmp -s "$CONFIG_SOURCE" "$CONFIG_DEPLOYED" || runtime_die 'Deployed Neovim lock differs from the repository source; preserve the customized runtime and review the installer snapshot before bootstrap.'

preflight_runtime_destinations() {
  if [[ -d "$LAZY_ROOT/.git" ]]; then
    [[ "$(git -C "$LAZY_ROOT" rev-parse HEAD 2>/dev/null || true)" == "$LAZY_COMMIT" ]] ||
      runtime_die 'Existing lazy.nvim checkout does not match the repository lock; refusing to overwrite customized runtime data.'
  else
    [[ ! -e "$LAZY_ROOT" ]] || runtime_die 'lazy.nvim runtime path exists but is not a managed Git checkout.'
  fi
  if [[ -e "$TREE_ROOT" ]]; then
    [[ -x "$TREE_ROOT/tree-sitter" && -f "$TREE_ROOT/.installed.tsv" ]] &&
      grep -Fqx $'tree-sitter\t0.27.0\t'"$TREE_SHA" "$TREE_ROOT/.installed.tsv" ||
      runtime_die 'Tree-sitter CLI destination exists without the exact pinned installation receipt.'
  fi
}

prepare_lazy() {
  if [[ -d "$LAZY_ROOT/.git" ]]; then
    return
  fi
  mkdir -p "$(dirname -- "$LAZY_ROOT")"
  local staging="$LAZY_ROOT.bootstrap.$$"
  trap 'rm -rf -- "$staging"' RETURN EXIT
  git clone --filter=blob:none https://github.com/folke/lazy.nvim.git "$staging" >/dev/null 2>&1
  git -C "$staging" checkout --detach "$LAZY_COMMIT" >/dev/null 2>&1
  [[ "$(git -C "$staging" rev-parse HEAD)" == "$LAZY_COMMIT" ]] || runtime_die 'lazy.nvim checkout did not resolve to the repository lock.'
  mv -- "$staging" "$LAZY_ROOT"
  staging=''
  trap - RETURN EXIT
}

prepare_tree_sitter() {
  if [[ -x "$TREE_ROOT/tree-sitter" && -f "$TREE_ROOT/.installed.tsv" ]] &&
    grep -Fqx $'tree-sitter\t0.27.0\t'"$TREE_SHA" "$TREE_ROOT/.installed.tsv"; then
    return
  fi
  [[ ! -e "$TREE_ROOT" ]] || runtime_die 'Tree-sitter CLI destination exists without the pinned executable.'
  mkdir -p "$(dirname -- "$TREE_ROOT")"
  local staging="$TREE_ROOT.bootstrap.$$" archive="$TREE_ROOT.bootstrap.$$.gz"
  trap 'rm -rf -- "$staging" "$archive"' RETURN EXIT
  mkdir -p "$staging"
  curl --fail --location --silent --show-error -o "$archive" "$TREE_URL"
  printf '%s  %s\n' "$TREE_SHA" "$archive" | sha256sum --check --status || runtime_die 'Tree-sitter CLI SHA256 mismatch.'
  gzip -cd -- "$archive" >"$staging/tree-sitter"
  chmod 0755 "$staging/tree-sitter"
  printf 'tree-sitter\t0.27.0\t%s\n' "$TREE_SHA" >"$staging/.installed.tsv"
  mv -- "$staging" "$TREE_ROOT"
  rm -f -- "$archive"
  staging=''; archive=''
  trap - RETURN EXIT
}

preflight_runtime_destinations
prepare_lazy
prepare_tree_sitter

MASON_BIN="$NVIM_DATA/mason/bin"
BOOTSTRAP_PATH="$HOME/.local/bin:$MASON_BIN:$TREE_ROOT:${PATH:-}"
OUTPUT="$(mktemp "${TMPDIR:-/tmp}/dotfiles-runtime-bootstrap.XXXXXX")"
cleanup_output() { rm -f -- "$OUTPUT"; }
trap cleanup_output EXIT

BOOTSTRAP_TIMEOUT_SECONDS=900
if [[ "${DOTFILES_WORKSTATION_TEST_MODE:-0}" == 1 && -n "${RUNTIME_TEST_TIMEOUT_SECONDS:-}" ]]; then
  [[ "$RUNTIME_TEST_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || runtime_die 'Test bootstrap timeout must be a positive integer.'
  BOOTSTRAP_TIMEOUT_SECONDS="$RUNTIME_TEST_TIMEOUT_SECONDS"
fi

set +e
(
  ulimit -c 0
  PATH="$BOOTSTRAP_PATH" \
  DOTFILES_RUNTIME_LOCK="$RUNTIME_LOCK" \
  DOTFILES_RUNTIME_LAZY_COMMIT="$LAZY_COMMIT" \
  LAZY="$LAZY_ROOT" \
    timeout --signal=TERM --kill-after=5s "${BOOTSTRAP_TIMEOUT_SECONDS}s" \
      nvim --headless -u "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.lua" -i NONE -l "$RUNTIME_LUA"
) >"$OUTPUT" 2>&1
status=$?
set -e
if ((status != 0)); then
  if grep -Fq 'RUNTIME_BOOTSTRAP_MARKSMAN_ICU' "$OUTPUT"; then
    checker="${DOTFILES_RUNTIME_CHECK:-$RUNTIME_UBUNTU_DIR/check-runtime.sh}"
    "$checker" --repair marksman-icu --approve-packages
  fi
  if ((status == 124)); then
    runtime_die "Neovim runtime bootstrap exceeded the bounded ${BOOTSTRAP_TIMEOUT_SECONDS}s timeout."
  fi
  if grep -Fq 'RUNTIME_BOOTSTRAP_FAILED' "$OUTPUT"; then
    printf '%s\n' 'Neovim runtime bootstrap detail:' >&2
    grep -A 2 -F 'RUNTIME_BOOTSTRAP_FAILED' "$OUTPUT" >&2 || true
  fi
  runtime_die "Neovim runtime bootstrap failed (status $status); inspect the package-specific detail above and Neovim/Mason logs locally."
fi
grep -Fq 'RUNTIME_BOOTSTRAP_OK' "$OUTPUT" || runtime_die 'Neovim bootstrap returned without its verified completion receipt.'
cmp -s "$CONFIG_SOURCE" "$CONFIG_DEPLOYED" || runtime_die 'Runtime bootstrap changed the managed Lazy lock; restore it from the installer snapshot before continuing.'

PATH="$BOOTSTRAP_PATH" "${DOTFILES_RUNTIME_CHECK:-$RUNTIME_UBUNTU_DIR/check-runtime.sh}"
runtime_log 'Pinned Neovim plugins, Mason packages, parser runtime, and core runtime checks completed.'
