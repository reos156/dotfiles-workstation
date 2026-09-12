#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPAIR=''
APPROVE_RUNTIME_REPAIR=0
APPROVE_DOWNLOADS=0
APPROVE_PACKAGES=0
FAILURES=0
REAL_HOME="${HOME:?HOME is required}"
REAL_DATA_HOME="${XDG_DATA_HOME:-$REAL_HOME/.local/share}"
MASON_BIN="$REAL_DATA_HOME/nvim/mason/bin"

usage() {
  cat <<'USAGE'
Usage:
  ubuntu/check-runtime.sh
  ubuntu/check-runtime.sh --repair vim-parser --approve-runtime-repair --approve-downloads
  ubuntu/check-runtime.sh --repair marksman-icu --approve-packages
  ubuntu/check-runtime.sh --repair paplay --approve-packages

Without arguments, this command performs read-only runtime diagnostics. Repairs are
outside the managed installer snapshot and require the approvals shown above.
USAGE
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
info() { printf '%s\n' "$*"; }

while (($#)); do
  case "$1" in
    --repair)
      [[ -z "$REPAIR" ]] || die 'Only one --repair selection is allowed.'
      (($# >= 2)) || die '--repair requires a capability name.'
      REPAIR="$2"
      shift
      ;;
    --approve-runtime-repair) APPROVE_RUNTIME_REPAIR=1 ;;
    --approve-downloads) APPROVE_DOWNLOADS=1 ;;
    --approve-packages) APPROVE_PACKAGES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

case "$REPAIR" in
  '')
    ((APPROVE_RUNTIME_REPAIR == 0 && APPROVE_DOWNLOADS == 0 && APPROVE_PACKAGES == 0)) ||
      die 'Approval flags are valid only with one matching --repair selection.'
    ;;
  vim-parser)
    ((APPROVE_RUNTIME_REPAIR == 1 && APPROVE_DOWNLOADS == 1 && APPROVE_PACKAGES == 0)) ||
      die 'vim-parser requires --approve-runtime-repair and --approve-downloads, and no package approval.'
    ;;
  marksman-icu|paplay)
    ((APPROVE_PACKAGES == 1 && APPROVE_RUNTIME_REPAIR == 0 && APPROVE_DOWNLOADS == 0)) ||
      die "$REPAIR requires --approve-packages and no runtime/download approval flags."
    ;;
  *) die "Unknown repair selection: $REPAIR" ;;
esac

ISOLATED_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-runtime-check.XXXXXX")"
cleanup() { rm -rf -- "$ISOLATED_ROOT"; }
trap cleanup EXIT
mkdir -p "$ISOLATED_ROOT/home" "$ISOLATED_ROOT/config" "$ISOLATED_ROOT/data" "$ISOLATED_ROOT/state" "$ISOLATED_ROOT/cache"

# This hook exists only for command-stub tests. It cannot be enabled accidentally
# during normal use because the installer's temporary-HOME test mode is required.
tool_forced_absent() {
  [[ "${DOTFILES_WORKSTATION_TEST_MODE:-0}" == 1 ]] || return 1
  local needle=",${DOTFILES_RUNTIME_TEST_ABSENT:-},"
  [[ "$needle" == *",$1,"* ]] || return 1
  [[ ! -e "${RUNTIME_TEST_LOG:-/nonexistent}.paplay-installed" || "$1" != paplay ]]
}

find_tool() {
  local name="$1" found=''
  if ! tool_forced_absent "$name"; then
    found="$(command -v "$name" 2>/dev/null || true)"
  fi
  if [[ -z "$found" && "$name" == marksman && -x "$MASON_BIN/marksman" ]]; then
    found="$MASON_BIN/marksman"
  fi
  printf '%s' "$found"
}

run_isolated() {
  HOME="$ISOLATED_ROOT/home" \
  XDG_CONFIG_HOME="$ISOLATED_ROOT/config" \
  XDG_DATA_HOME="$REAL_DATA_HOME" \
  XDG_STATE_HOME="$ISOLATED_ROOT/state" \
  XDG_CACHE_HOME="$ISOLATED_ROOT/cache" \
    "$@"
}

NVIM="$(find_tool nvim)"
TS_ROOT="$REAL_DATA_HOME/nvim/lazy/nvim-treesitter"
NVIM_SITE="$REAL_DATA_HOME/nvim/site"
VIM_PARSER="$NVIM_SITE/parser/vim.so"
VIM_QUERY="$TS_ROOT/runtime/queries/vim/highlights.scm"
VIM_STATUS='optional'

check_vim_query() {
  VIM_STATUS='optional'
  if [[ -z "$NVIM" ]]; then
    info 'OPTIONAL vim-query: Neovim is not installed.'
    return 2
  fi
  if [[ ! -d "$TS_ROOT" ]]; then
    info 'OPTIONAL vim-query: nvim-treesitter is not installed in the standard data runtime.'
    return 2
  fi
  if [[ ! -f "$VIM_PARSER" ]]; then
    VIM_STATUS='missing-parser'
    info 'FAIL vim-query: nvim-treesitter is installed but the Vim parser is absent.'
    return 1
  fi
  if [[ ! -f "$VIM_QUERY" ]]; then
    VIM_STATUS='missing-query-file'
    info 'FAIL vim-query: nvim-treesitter is installed but its Vim highlights query file is absent.'
    return 1
  fi

  local lua status
  lua="vim.opt.rtp:prepend([=[$NVIM_SITE]=]); vim.opt.rtp:prepend([=[$TS_ROOT]=]); local ok,q=pcall(vim.treesitter.query.get,'vim','highlights'); if not ok then vim.cmd('cquit 4') elseif q == nil then vim.cmd('cquit 3') end"
  set +e
  run_isolated "$NVIM" --headless -u NONE -i NONE --noplugin --cmd "lua $lua" +qa >/dev/null 2>&1
  status=$?
  set -e
  case "$status" in
    0) VIM_STATUS='healthy'; info 'OK vim-query: Vim highlights query compiles.'; return 0 ;;
    3) VIM_STATUS='missing-query'; info 'FAIL vim-query: Vim highlights query is missing from the loaded runtime.'; return 1 ;;
    *) VIM_STATUS='failed'; info 'FAIL vim-query: Vim highlights query does not compile in the isolated runtime check.'; return 1 ;;
  esac
}

MARKSMAN="$(find_tool marksman)"
MARKSMAN_STATUS='optional'
check_marksman() {
  MARKSMAN_STATUS='optional'
  if [[ -z "$MARKSMAN" ]]; then
    info 'OPTIONAL marksman: not installed.'
    return 2
  fi
  local error_file="$ISOLATED_ROOT/marksman.stderr" status
  set +e
  (ulimit -c 0; run_isolated "$MARKSMAN" --version >/dev/null 2>"$error_file")
  status=$?
  set -e
  if ((status == 0)); then
    MARKSMAN_STATUS='healthy'
    info 'OK marksman: version check passed.'
    return 0
  fi
  if grep -Fq "Couldn't find a valid ICU package installed on the system" "$error_file"; then
    MARKSMAN_STATUS='icu'
    info 'FAIL marksman: ICU runtime package is unavailable.'
  else
    MARKSMAN_STATUS='other'
    info 'FAIL marksman: version check failed for a reason other than missing ICU.'
  fi
  return 1
}

HERDR="$(find_tool herdr)"
PAPLAY="$(find_tool paplay)"
PAPLAY_STATUS='optional'
check_paplay() {
  PAPLAY_STATUS='optional'
  if [[ -z "$HERDR" ]]; then
    info 'OPTIONAL paplay: Herdr is not installed.'
    return 2
  fi
  if [[ -z "$PAPLAY" ]]; then
    PAPLAY_STATUS='missing'
    info 'FAIL paplay: command is unavailable for the installed Herdr integration.'
    return 1
  fi
  PAPLAY_STATUS='healthy'
  info 'OK paplay: command is available (audio was not played).'
  return 0
}

run_check() {
  local function="$1"
  if "$function"; then return 0; else
    local status=$?
    ((status == 2)) || FAILURES=$((FAILURES + 1))
    return 0
  fi
}

repair_vim_parser() {
  run_check check_vim_query
  case "$VIM_STATUS" in
    healthy|optional) info 'NO-OP vim-parser: selected capability is healthy or its optional parent runtime is absent.'; return 0 ;;
  esac
  [[ -d "$TS_ROOT/lua/nvim-treesitter" ]] ||
    die 'Installed nvim-treesitter does not expose its Lua module; use the plugin-supported manual repair workflow.'
  info 'WARNING: this downloads one Vim parser and changes runtime data outside managed snapshots; automatic rollback is unavailable.'
  local lua status
  lua="vim.opt.rtp:prepend([=[$NVIM_SITE]=]); vim.opt.rtp:prepend([=[$TS_ROOT]=]); local ok=require('nvim-treesitter.install').install({'vim'}, {force=true, summary=true}):pwait(600000); assert(ok, 'Vim parser install did not complete')"
  set +e
  run_isolated "$NVIM" --headless -u NONE -i NONE --noplugin --cmd "lua $lua" +qa >/dev/null 2>&1
  status=$?
  set -e
  ((status == 0)) || die 'The targeted Vim parser repair failed; inspect the installed nvim-treesitter API and repair manually.'
  FAILURES=0
  run_check check_vim_query
  case "$VIM_STATUS" in
    healthy) return 0 ;;
    missing-parser) die 'The Vim parser is still absent after targeted repair; use the installed plugin supported workflow manually.' ;;
    missing-query-file) die 'The nvim-treesitter Vim plugin query is still absent after parser repair; review or restore the plugin checkout manually.' ;;
    missing-query) die 'The Vim highlights query is still missing after parser repair; inspect runtime compatibility manually.' ;;
    *) die 'The Vim query still fails after targeted parser repair.' ;;
  esac
}

os_release_path() {
  if [[ "${DOTFILES_WORKSTATION_TEST_MODE:-0}" == 1 && -n "${DOTFILES_RUNTIME_TEST_OS_RELEASE:-}" ]]; then
    printf '%s' "$DOTFILES_RUNTIME_TEST_OS_RELEASE"
  else
    printf '/etc/os-release'
  fi
}

select_icu_package() {
  local release_file id candidate package
  release_file="$(os_release_path)"
  [[ -r "$release_file" ]] || die 'Cannot verify Ubuntu for ICU package repair.'
  id="$(awk -F= '$1 == "ID" {gsub(/"/, "", $2); print $2; exit}' "$release_file")"
  [[ "$id" == ubuntu ]] || die 'ICU package repair is supported only on Ubuntu.'
  command -v apt-cache >/dev/null 2>&1 || die 'apt-cache is required to review current ICU package metadata.'
  local -a candidates=()
  while IFS= read -r package; do
    [[ "$package" =~ ^libicu[0-9]+$ ]] || continue
    candidate="$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    [[ -n "$candidate" && "$candidate" != '(none)' ]] && candidates+=("$package")
  done < <(apt-cache pkgnames 2>/dev/null | sort -u)
  ((${#candidates[@]} == 1)) ||
    die "Current apt metadata found ${#candidates[@]} installable libicu candidates; review packages manually."
  printf '%s' "${candidates[0]}"
}

repair_marksman_icu() {
  run_check check_marksman
  case "$MARKSMAN_STATUS" in
    healthy|optional) info 'NO-OP marksman-icu: selected capability is healthy or Marksman is absent.'; return 0 ;;
    other) die 'Marksman did not emit the exact missing-ICU diagnostic; no package repair was attempted.' ;;
  esac
  local package
  package="$(select_icu_package)"
  info "WARNING: sudo may request authentication in an interactive terminal. Installing $package has no automated rollback."
  sudo apt-get install --no-install-recommends --no-upgrade "$package"
  FAILURES=0
  run_check check_marksman
  ((FAILURES == 0)) && [[ "$MARKSMAN_STATUS" == healthy ]] || die 'Marksman still fails after the approved ICU package repair.'
}

repair_paplay() {
  run_check check_paplay
  case "$PAPLAY_STATUS" in
    healthy|optional) info 'NO-OP paplay: selected capability is healthy or Herdr is absent.'; return 0 ;;
  esac
  local release_file id
  release_file="$(os_release_path)"
  [[ -r "$release_file" ]] || die 'Cannot verify Ubuntu for paplay package repair.'
  id="$(awk -F= '$1 == "ID" {gsub(/"/, "", $2); print $2; exit}' "$release_file")"
  [[ "$id" == ubuntu ]] || die 'paplay package repair is supported only on Ubuntu.'
  info 'WARNING: sudo may request authentication in an interactive terminal. Package rollback is not automated.'
  sudo apt-get install --no-install-recommends --no-upgrade pulseaudio-utils
  if [[ "${DOTFILES_WORKSTATION_TEST_MODE:-0}" == 1 && -n "${RUNTIME_TEST_LOG:-}" ]]; then
    : >"${RUNTIME_TEST_LOG}.paplay-installed"
  fi
  PAPLAY="$(find_tool paplay)"
  FAILURES=0
  run_check check_paplay
  ((FAILURES == 0)) && [[ "$PAPLAY_STATUS" == healthy ]] || die 'paplay is still unavailable after the approved package repair.'
}

case "$REPAIR" in
  vim-parser) repair_vim_parser ;;
  marksman-icu) repair_marksman_icu ;;
  paplay) repair_paplay ;;
  '')
    run_check check_vim_query
    run_check check_marksman
    run_check check_paplay
    ((FAILURES == 0))
    ;;
esac
