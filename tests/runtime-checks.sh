#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"
CHECK="$ROOT/ubuntu/check-runtime.sh"
CASE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/runtime-check-tests.XXXXXX")"
trap 'rm -rf -- "$CASE_ROOT"' EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "missing '$2' in ${1##*/}"; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || fail "unexpected '$2' in ${1##*/}"; }

make_case() {
  CASE="$CASE_ROOT/$1"
  mkdir -p "$CASE/home" "$CASE/bin" \
    "$CASE/data/nvim/lazy/nvim-treesitter/runtime/queries/vim" \
    "$CASE/data/nvim/lazy/nvim-treesitter/lua/nvim-treesitter" \
    "$CASE/data/nvim/site/parser"
  : >"$CASE/data/nvim/site/parser/vim.so"
  : >"$CASE/data/nvim/lazy/nvim-treesitter/runtime/queries/vim/highlights.scm"
  LOG="$CASE/commands.log"
  : >"$LOG"
  export HOME="$CASE/home"
  export XDG_CONFIG_HOME="$CASE/home/config"
  export XDG_DATA_HOME="$CASE/data"
  export XDG_STATE_HOME="$CASE/home/state"
  export XDG_CACHE_HOME="$CASE/home/cache"
  export DOTFILES_WORKSTATION_TEST_MODE=1
  export DOTFILES_RUNTIME_TEST_OS_RELEASE="$CASE/os-release"
  export DOTFILES_RUNTIME_TEST_ABSENT=''
  export RUNTIME_TEST_LOG="$LOG"
  export STUB_NVIM_CHECK=healthy
  export STUB_NVIM_REPAIR=success
  export STUB_NVIM_REPAIR_FIX_CHECK=1
  export STUB_PARSER_PATH="$CASE/data/nvim/site/parser/vim.so"
  export STUB_MARKSMAN=healthy
  export STUB_APT_PACKAGES='libicu99'
  printf 'ID=ubuntu\n' >"$CASE/os-release"

  cat >"$CASE/bin/nvim" <<'STUB'
#!/usr/bin/env bash
printf 'nvim HOME=%s CONFIG=%s DATA=%s STATE=%s CACHE=%s ARGS=%s\n' \
  "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$*" >>"$RUNTIME_TEST_LOG"
if [[ "$*" == *"nvim-treesitter.install"* ]]; then
  [[ "$STUB_NVIM_REPAIR" == success ]] || exit 9
  [[ -z "${STUB_PARSER_PATH:-}" ]] || : >"$STUB_PARSER_PATH"
  [[ "${STUB_NVIM_REPAIR_FIX_CHECK:-1}" == 1 ]] && : >"${RUNTIME_TEST_LOG}.parser-fixed"
  exit 0
fi
[[ -f "${RUNTIME_TEST_LOG}.parser-fixed" ]] && exit 0
case "$STUB_NVIM_CHECK" in healthy) exit 0;; missing) exit 3;; compile) exit 4;; esac
exit 8
STUB
  cat >"$CASE/bin/marksman" <<'STUB'
#!/usr/bin/env bash
printf 'marksman ARGS=%s\n' "$*" >>"$RUNTIME_TEST_LOG"
case "$STUB_MARKSMAN" in
  healthy) printf 'Marksman test\n'; exit 0;;
  icu) printf "Couldn't find a valid ICU package installed on the system\n" >&2; exit 134;;
  other) printf 'private raw crash detail\n' >&2; exit 2;;
esac
STUB
  cat >"$CASE/bin/herdr" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  cat >"$CASE/bin/paplay" <<'STUB'
#!/usr/bin/env bash
printf 'paplay invoked\n' >>"$RUNTIME_TEST_LOG"
exit 0
STUB
  cat >"$CASE/bin/apt-cache" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == pkgnames ]]; then
  tr ',' '\n' <<<"$STUB_APT_PACKAGES"
elif [[ "$1" == policy ]]; then
  printf '%s:\n  Candidate: 1.test\n' "$2"
fi
STUB
  cat >"$CASE/bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$RUNTIME_TEST_LOG"
exit 0
STUB
  chmod +x "$CASE/bin/"*
  export PATH="$CASE/bin:$ORIGINAL_PATH"
}

ORIGINAL_PATH="$PATH"

make_case default-read-only
before="$(find "$CASE/home" -mindepth 1 -print | sort)"
"$CHECK" >"$CASE/out" 2>"$CASE/err"
after="$(find "$CASE/home" -mindepth 1 -print | sort)"
[[ "$before" == "$after" ]] || fail 'default diagnostics left isolated state behind'
assert_not_contains "$LOG" 'sudo '
assert_not_contains "$LOG" 'paplay invoked'
assert_contains "$LOG" '-u NONE -i NONE --noplugin'
assert_contains "$LOG" "DATA=$CASE/data"
assert_not_contains "$LOG" 'init.lua'
pass 'default diagnostics are isolated and non-mutating'

make_case absent-optionals
export DOTFILES_RUNTIME_TEST_ABSENT='nvim,marksman,herdr,paplay'
"$CHECK" >"$CASE/out" 2>"$CASE/err"
assert_contains "$CASE/out" 'OPTIONAL vim-query: Neovim is not installed'
assert_contains "$CASE/out" 'OPTIONAL marksman: not installed'
assert_contains "$CASE/out" 'OPTIONAL paplay: Herdr is not installed'
[[ ! -s "$LOG" ]] || fail 'absent optional tools were executed'
pass 'absent parent tools remain optional and are not executed'

make_case marksman-icu
export STUB_MARKSMAN=icu
if "$CHECK" >"$CASE/out" 2>"$CASE/err"; then fail 'ICU failure passed diagnostics'; fi
assert_contains "$CASE/out" 'FAIL marksman: ICU runtime package is unavailable'
assert_not_contains "$CASE/out" 'private raw'
assert_not_contains "$CASE/err" "Couldn't find"
pass 'Marksman exact ICU failure is classified without raw stderr'

make_case marksman-other
export STUB_MARKSMAN=other
if "$CHECK" >"$CASE/out" 2>"$CASE/err"; then fail 'other Marksman failure passed diagnostics'; fi
assert_contains "$CASE/out" 'FAIL marksman: version check failed for a reason other than missing ICU'
assert_not_contains "$CASE/out" 'private raw crash detail'
pass 'non-ICU Marksman failures stay distinct and redacted'

make_case approvals
for args in \
  '--repair vim-parser --approve-downloads' \
  '--repair vim-parser --approve-runtime-repair' \
  '--repair marksman-icu' \
  '--repair paplay' \
  '--repair unknown --approve-packages'; do
  if "$CHECK" $args >"$CASE/out" 2>"$CASE/err"; then fail "invalid approval set passed: $args"; fi
done
if "$CHECK" --repair vim-parser --repair paplay --approve-runtime-repair --approve-downloads --approve-packages >"$CASE/out" 2>"$CASE/err"; then
  fail 'multiple repair selections passed'
fi
[[ ! -s "$LOG" ]] || fail 'invalid repair request executed a tool'
pass 'unknown, multiple, and mismatched approvals fail before tool execution'

make_case parser-repair
export STUB_NVIM_CHECK=compile
if ! "$CHECK" --repair vim-parser --approve-runtime-repair --approve-downloads >"$CASE/out" 2>"$CASE/err"; then
  cat "$CASE/out" "$CASE/err" >&2
  fail 'targeted parser repair unexpectedly failed'
fi
assert_contains "$LOG" "nvim-treesitter.install"
assert_contains "$LOG" "install({'vim'}, {force=true, summary=true}):pwait(600000)"
assert_contains "$LOG" '-u NONE -i NONE --noplugin'
assert_contains "$LOG" "$CASE/data/nvim/lazy/nvim-treesitter"
assert_not_contains "$LOG" 'Lazy update'
[[ "$(grep -c '^nvim ' "$LOG")" -eq 3 ]] || fail 'parser repair did not check, repair, and recheck exactly'
first_home="$(awk 'NR==1 {sub(/^nvim HOME=/, ""); sub(/ CONFIG=.*/, ""); print}' "$LOG")"
[[ "$first_home" != "$HOME" && "$first_home" == /tmp/* ]] || fail 'Neovim did not receive an isolated HOME'
pass 'parser repair uses only targeted supported API, bounded wait, and isolated flags'

make_case healthy-noop
"$CHECK" --repair vim-parser --approve-runtime-repair --approve-downloads >"$CASE/out" 2>"$CASE/err"
[[ "$(grep -c '^nvim ' "$LOG")" -eq 1 ]] || fail 'healthy parser triggered repair or extra check'
assert_not_contains "$LOG" 'nvim-treesitter.install'
pass 'healthy selected capability is a no-op'

make_case missing-query
export STUB_NVIM_CHECK=missing
if "$CHECK" >"$CASE/out" 2>"$CASE/err"; then fail 'nil Vim query passed diagnostics'; fi
assert_contains "$CASE/out" 'FAIL vim-query: Vim highlights query is missing from the loaded runtime'
pass 'nil Vim query is reported as a detected failure rather than a compile success'

make_case missing-parser-approved
rm "$CASE/data/nvim/site/parser/vim.so"
"$CHECK" --repair vim-parser --approve-runtime-repair --approve-downloads >"$CASE/out" 2>"$CASE/err"
assert_contains "$LOG" 'nvim-treesitter.install'
[[ -f "$CASE/data/nvim/site/parser/vim.so" ]] || fail 'targeted parser repair did not restore the missing parser fixture'
pass 'installed plugin with physically missing parser permits targeted approved repair'

make_case missing-query-approved
rm "$CASE/data/nvim/lazy/nvim-treesitter/runtime/queries/vim/highlights.scm"
if "$CHECK" --repair vim-parser --approve-runtime-repair --approve-downloads >"$CASE/out" 2>"$CASE/err"; then
  fail 'physically missing plugin query returned repair success'
fi
assert_contains "$LOG" 'nvim-treesitter.install'
assert_contains "$CASE/err" 'plugin query is still absent'
pass 'physically missing plugin query fails after targeted repair with manual remediation'

make_case nil-query-approved
export STUB_NVIM_CHECK=missing
export STUB_NVIM_REPAIR_FIX_CHECK=0
if "$CHECK" --repair vim-parser --approve-runtime-repair --approve-downloads >"$CASE/out" 2>"$CASE/err"; then
  fail 'persistently nil query returned repair success'
fi
assert_contains "$LOG" 'nvim-treesitter.install'
assert_contains "$CASE/err" 'Vim highlights query is still missing'
pass 'stubbed nil query status remains a failure after approved repair and recheck'

make_case absent-plugin-approved
mv "$CASE/data/nvim/lazy/nvim-treesitter" "$CASE/data/nvim/lazy/nvim-treesitter.absent"
"$CHECK" --repair vim-parser --approve-runtime-repair --approve-downloads >"$CASE/out" 2>"$CASE/err"
assert_contains "$CASE/out" 'OPTIONAL vim-query: nvim-treesitter is not installed'
assert_contains "$CASE/out" 'NO-OP vim-parser'
assert_not_contains "$LOG" 'nvim-treesitter.install'
pass 'absent nvim-treesitter parent remains an approved no-op'

make_case parser-api-unavailable
export STUB_NVIM_CHECK=compile
rmdir "$CASE/data/nvim/lazy/nvim-treesitter/lua/nvim-treesitter"
if "$CHECK" --repair vim-parser --approve-runtime-repair --approve-downloads >"$CASE/out" 2>"$CASE/err"; then
  fail 'missing installed parser API triggered a successful repair'
fi
assert_contains "$CASE/err" 'does not expose its Lua module'
assert_not_contains "$LOG" 'nvim-treesitter.install'
pass 'unavailable installed parser API fails with manual guidance and no bootstrap'

make_case icu-ambiguity
export STUB_MARKSMAN=icu
export STUB_APT_PACKAGES='libicu98,libicu99'
if "$CHECK" --repair marksman-icu --approve-packages >"$CASE/out" 2>"$CASE/err"; then fail 'ambiguous ICU candidates passed'; fi
assert_contains "$CASE/err" 'found 2 installable libicu candidates'
assert_not_contains "$LOG" 'sudo '
pass 'multiple ICU candidates fail closed before sudo'

make_case icu-zero-candidates
export STUB_MARKSMAN=icu
export STUB_APT_PACKAGES='libicu-dev,unrelated'
if "$CHECK" --repair marksman-icu --approve-packages >"$CASE/out" 2>"$CASE/err"; then fail 'zero ICU candidates passed'; fi
assert_contains "$CASE/err" 'found 0 installable libicu candidates'
assert_not_contains "$LOG" 'sudo '
pass 'zero ICU candidates fail closed without guessing a package'

make_case icu-postrepair-failure
export STUB_MARKSMAN=icu
if "$CHECK" --repair marksman-icu --approve-packages >"$CASE/out" 2>"$CASE/err"; then
  fail 'unchanged Marksman failure passed after package command'
fi
assert_contains "$CASE/err" 'still fails after the approved ICU package repair'
assert_contains "$LOG" 'sudo apt-get install --no-install-recommends --no-upgrade libicu99'
pass 'package repair returns nonzero when the selected capability still fails'

make_case icu-repair
export STUB_MARKSMAN=icu
# The sudo stub changes the subsequent Marksman result without installing anything.
cat >"$CASE/bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$RUNTIME_TEST_LOG"
export_line="export STUB_MARKSMAN=healthy"
printf '%s\n' "$export_line" >"${RUNTIME_TEST_LOG}.marksman-fixed"
exit 0
STUB
cat >"$CASE/bin/marksman" <<'STUB'
#!/usr/bin/env bash
[[ -f "${RUNTIME_TEST_LOG}.marksman-fixed" ]] && exit 0
printf "Couldn't find a valid ICU package installed on the system\n" >&2
exit 134
STUB
chmod +x "$CASE/bin/sudo" "$CASE/bin/marksman"
"$CHECK" --repair marksman-icu --approve-packages >"$CASE/out" 2>"$CASE/err"
assert_contains "$LOG" 'sudo apt-get install --no-install-recommends --no-upgrade libicu99'
pass 'approved ICU repair installs only the uniquely discovered dependency and rechecks'

make_case paplay-repair
export DOTFILES_RUNTIME_TEST_ABSENT='paplay'
"$CHECK" --repair paplay --approve-packages >"$CASE/out" 2>"$CASE/err"
assert_contains "$LOG" 'sudo apt-get install --no-install-recommends --no-upgrade pulseaudio-utils'
assert_not_contains "$LOG" 'paplay invoked'
pass 'paplay repair is package-only when Herdr is relevant and never plays audio'

make_case postrepair-failure
export STUB_NVIM_CHECK=compile
export STUB_NVIM_REPAIR=failure
if "$CHECK" --repair vim-parser --approve-runtime-repair --approve-downloads >"$CASE/out" 2>"$CASE/err"; then
  fail 'failed parser repair returned success'
fi
assert_contains "$CASE/err" 'targeted Vim parser repair failed'
pass 'repair and post-repair failures propagate nonzero'

printf 'All runtime-check tests passed.\n'
