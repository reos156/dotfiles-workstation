#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"
NVIM_SOURCE="$ROOT/ubuntu/config/nvim"

bash -n "$ROOT/ubuntu/install.sh" "$ROOT/ubuntu/check-runtime.sh" "$ROOT/ubuntu/verify.sh" "$ROOT/ubuntu/rollback.sh" "$ROOT/ubuntu/lib/common.sh" "$TEST_DIR/run.sh" "$TEST_DIR/runtime-checks.sh" "$TEST_DIR/sanitize.sh" "$TEST_DIR/nvim-inventory.sh" "$TEST_DIR/bootstrap.sh"
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/ubuntu/config/zsh/.zshrc"
fi
printf 'ok - shell syntax is valid\n'

CASE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-workstation-tests.XXXXXX")"
KEEP_ARTIFACTS="${DOTFILES_WORKSTATION_KEEP_TEST_ARTIFACTS:-0}"
cleanup() {
  if [[ "$KEEP_ARTIFACTS" == 1 ]]; then
    printf 'Debug artifacts preserved under system temporary storage (%s).\n' "${CASE_DIR##*/}"
  else
    rm -rf -- "$CASE_DIR"
  fi
}
trap cleanup EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_file() { [[ -f "$1" && ! -L "$1" ]] || fail "expected regular file: $1"; }
assert_not_exists() { [[ ! -e "$1" && ! -L "$1" ]] || fail "expected absent path: $1"; }

SANITIZE_REPO="$CASE_DIR/sanitize-repo"
mkdir -p "$SANITIZE_REPO/tests" "$SANITIZE_REPO/.atl"
cp -- "$TEST_DIR/sanitize.sh" "$SANITIZE_REPO/tests/sanitize.sh"
printf 'safe tracked payload\n' >"$SANITIZE_REPO/README.md"
printf '.atl/\n' >"$SANITIZE_REPO/.gitignore"
printf '/home/%s/private\naccess_%s = generated-only\n' 'generated-user' 'token' >"$SANITIZE_REPO/.atl/generated.log"
git -C "$SANITIZE_REPO" init -q
git -C "$SANITIZE_REPO" add tests/sanitize.sh README.md .gitignore
if ! "$SANITIZE_REPO/tests/sanitize.sh" >"$CASE_DIR/sanitize-ignored.out" 2>&1; then
  fail 'sanitizer rejected ignored or untracked generated workspace state'
fi
pass 'sanitizer ignores generated workspace state outside Git-tracked content'

SANITIZE_ARCHIVE="$CASE_DIR/sanitize-archive"
mkdir -p "$SANITIZE_ARCHIVE/tests"
cp -- "$TEST_DIR/sanitize.sh" "$SANITIZE_ARCHIVE/tests/sanitize.sh"
printf '/home/%s/private\n' 'archive-user' >"$SANITIZE_ARCHIVE/tracked-payload.txt"
if "$SANITIZE_ARCHIVE/tests/sanitize.sh" >"$CASE_DIR/sanitize-archive-payload.out" 2>&1; then
  fail 'archive sanitizer accepted a machine-specific path payload'
fi
grep -Fq 'machine-specific home path found' "$CASE_DIR/sanitize-archive-payload.out" || fail 'archive sanitizer failed for the wrong reason'
pass 'sanitizer rejects tracked-like archive payloads without Git metadata'

assert_archive_credential_rejected() {
  local label="$1" payload_kind="$2"
  local fixture="$CASE_DIR/sanitize-credential-$payload_kind"
  mkdir -p "$fixture/tests"
  cp -- "$TEST_DIR/sanitize.sh" "$fixture/tests/sanitize.sh"
  case "$payload_kind" in
    password) printf '%s = %s\n' 'password' 'hunter2' >"$fixture/payload.txt" ;;
    token) printf '%s = %s%s\n' 'token' 'ghp_' 'exampleSecretValue1234567890' >"$fixture/payload.txt" ;;
    private-key)
      printf '%s%s%s\n%s\n%s%s%s\n' \
        '-----BEGIN ' 'OPENSSH PRIVATE' ' KEY-----' \
        'representative-key-material' \
        '-----END ' 'OPENSSH PRIVATE' ' KEY-----' >"$fixture/payload.txt"
      ;;
    *) fail "unknown sanitizer credential fixture: $payload_kind" ;;
  esac
  if "$fixture/tests/sanitize.sh" >"$CASE_DIR/sanitize-$payload_kind.out" 2>&1; then
    fail "sanitizer accepted tracked-like $label payload"
  fi
  grep -Fq 'credential-like payload found' "$CASE_DIR/sanitize-$payload_kind.out" || fail "sanitizer rejected $label payload for the wrong reason"
  pass "sanitizer rejects tracked-like $label payload"
}

assert_archive_credential_rejected 'password assignment' password
assert_archive_credential_rejected 'generic token assignment' token
assert_archive_credential_rejected 'OpenSSH private-key block' private-key

"$TEST_DIR/sanitize.sh"
"$TEST_DIR/nvim-inventory.sh"
# Run this path directly: the tracked-only archive fixture intentionally excludes
# new untracked files from its copied tree.
"$TEST_DIR/runtime-checks.sh"

TEST_HOME="$CASE_DIR/home"
mkdir -p "$TEST_HOME"
export HOME="$TEST_HOME"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export DOTFILES_WORKSTATION_TEST_MODE=1

if command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool "$NVIM_SOURCE/lazy-lock.json" >/dev/null
  python3 -m json.tool "$NVIM_SOURCE/lazyvim.json" >/dev/null
  printf 'ok - Neovim JSON metadata parses\n'
fi

lua_failures=0
while IFS= read -r -d '' lua_file; do
  if command -v luac >/dev/null 2>&1; then
    luac -p "$lua_file" || lua_failures=$((lua_failures + 1))
  elif command -v nvim >/dev/null 2>&1; then
    nvim --headless -u NONE -i NONE --cmd "lua assert(loadfile([=[$lua_file]=]))" +qa >/dev/null 2>&1 || lua_failures=$((lua_failures + 1))
  fi
done < <(find "$NVIM_SOURCE" -type f -name '*.lua' -print0)
[[ "$lua_failures" -eq 0 ]] || { printf 'not ok - Lua parsing failed\n' >&2; exit 1; }
printf 'ok - Lua sources parse where a parser is available\n'

grep -Fq 'local linuxbrew_bin = "/home/linuxbrew/.linuxbrew/bin"' "$NVIM_SOURCE/init.lua" || fail 'default Linuxbrew prefix detection is missing'
grep -Fq 'vim.fn.isdirectory(linuxbrew_bin) == 1' "$NVIM_SOURCE/init.lua" || fail 'default Linuxbrew detection must not depend on brew already being in PATH'
grep -Fq 'vim.fn.system({ "brew", "--prefix" })' "$NVIM_SOURCE/init.lua" || fail 'dynamic Homebrew prefix discovery is missing'
printf 'ok - default and dynamic Homebrew discovery are statically explicit\n'

if command -v nvim >/dev/null 2>&1; then
  DOTFILES_TEST_NVIM_INIT="$NVIM_SOURCE/init.lua" nvim --headless -u NONE -i NONE \
    --cmd "luafile $TEST_DIR/nvim-init-portability.lua" +qa >/dev/null
  printf 'ok - init exposes simulated default and dynamic Homebrew prefixes without network\n'

  if [[ -n "${DOTFILES_ACTIVE_NVIM_ROOT:-}" ]]; then
    DOTFILES_TEST_ACTIVE_UI="$DOTFILES_ACTIVE_NVIM_ROOT/lua/plugins/ui.lua" \
      DOTFILES_TEST_PUBLISHED_UI="$NVIM_SOURCE/lua/plugins/ui.lua" \
      nvim --headless -u NONE -i NONE --cmd "luafile $TEST_DIR/nvim-header-equivalence.lua" +qa >/dev/null
    printf 'ok - evaluated dashboard header matches the active source byte-for-byte\n'
  else
    printf 'OPTIONAL active dashboard comparison (set DOTFILES_ACTIVE_NVIM_ROOT)\n'
  fi

  nvim --headless -u NONE -i NONE \
    --cmd "lua vim.opt.rtp:prepend([=[$NVIM_SOURCE]=])" \
    --cmd "lua assert(type(require('config.nodejs')) == 'table')" \
    --cmd "lua assert(type(require('config.gentleman.utils')) == 'table')" \
    --cmd "lua assert(type(dofile([=[$NVIM_SOURCE/lua/plugins/obsidian.lua]=])) == 'table')" \
    --cmd "lua assert(type(dofile([=[$NVIM_SOURCE/lua/plugins/minidiff.lua]=])) == 'table')" \
    +qa >/dev/null
  printf 'ok - portable standalone modules load without plugins or network\n'
fi

for color in '#66cc66' '#303a30' '#cc6666' '#3a3030' '#ffcccc' '#612626' '#ccffcc' '#266126'; do
  grep -Fq "$color" "$NVIM_SOURCE/lua/plugins/minidiff.lua" || { printf 'Missing MiniDiff color: %s\n' "$color" >&2; exit 1; }
done
grep -Fq 'MiniDiffUpdated' "$NVIM_SOURCE/lua/plugins/minidiff.lua"
printf 'ok - source MiniDiff palette and overlay behavior are preserved\n'

grep -Fq 'stage: 2' "$ROOT/manifest.yaml"
grep -Fq 'ubuntu/config/nvim' "$ROOT/manifest.yaml"
grep -Fq 'destination: ${XDG_CONFIG_HOME:-$HOME/.config}/nvim' "$ROOT/manifest.yaml"
printf 'ok - manifest declares the stage-2 managed directory\n'

SOURCE_BASELINE="$ROOT/docs/source-baseline-2026-09-11.md"
grep -Fq 'docs/source-baseline-2026-09-11.md' "$ROOT/README.md" || fail 'README does not link the versioned source baseline'
grep -Fq 'document: docs/source-baseline-2026-09-11.md' "$ROOT/manifest.yaml" || fail 'manifest does not reference the versioned source baseline'
grep -Fq 'status: versioned-observed-reference' "$ROOT/manifest.yaml" || fail 'manifest does not declare the observed-reference status'
grep -Fq 'versioned observed reference' "$SOURCE_BASELINE" || fail 'source baseline does not state its observed-reference status'
grep -Fq '| ca-certificates | version not captured/unresolved |' "$SOURCE_BASELINE" || fail 'source baseline omits unresolved ca-certificates evidence'
grep -Fq '| win32yank.exe | version not captured/unresolved |' "$SOURCE_BASELINE" || fail 'source baseline omits unresolved win32yank evidence'
pass 'README, manifest, and source baseline preserve the observed-reference contract'

for archive_document in "$ROOT/README.md" "$ROOT/manifest.yaml"; do
  for archive_flag in '--null' '--files-from=-' '--no-recursion' '--sort=name' "--mtime='@0'" '--owner=0' '--group=0' '--numeric-owner' '--format=posix' '--pax-option=delete=atime,delete=ctime' 'gzip -n'; do
    grep -Fq -- "$archive_flag" "$archive_document" || fail "normalized archive flag is undocumented in $archive_document: $archive_flag"
  done
done
grep -Fq 'Git is the canonical distribution path.' "$ROOT/README.md" || fail 'Git canonical distribution guidance is missing'
grep -Fq 'repository file contents cannot control metadata added by an arbitrary archiver' "$ROOT/README.md" || fail 'archive metadata boundary is missing'
archive_command="$(grep -A2 -F 'git ls-files -z | tar' "$ROOT/README.md")"
archive_before_file_list="${archive_command%%--files-from=-*}"
[[ "$archive_before_file_list" == *'--null'* && "$archive_before_file_list" == *'--no-recursion'* && "$archive_before_file_list" == *'-cf -'* ]] || fail 'README positional tar options must precede --files-from=-'
manifest_archive_command="$(grep -A2 -F 'git ls-files -z | tar' "$ROOT/manifest.yaml")"
manifest_before_file_list="${manifest_archive_command%%--files-from=-*}"
[[ "$manifest_before_file_list" == *'--null'* && "$manifest_before_file_list" == *'--no-recursion'* && "$manifest_before_file_list" == *'-cf -'* ]] || fail 'manifest positional tar options must precede --files-from=-'
pass 'normalized archive fallback and metadata boundary are documented'

ARCHIVE_FIXTURE="$CASE_DIR/archive-fixture"
ARCHIVE_ONE="$CASE_DIR/dotfiles-workstation-one.tar.gz"
ARCHIVE_TWO="$CASE_DIR/dotfiles-workstation-two.tar.gz"
mkdir -p "$ARCHIVE_FIXTURE"
# Export current tracked working-tree bytes only, so unrelated ignored or
# untracked workspace state cannot become archive payload by accident.
(
  cd -- "$ROOT"
  git ls-files -z | tar -cf - --null --no-recursion --files-from=-
) | tar -xf - -C "$ARCHIVE_FIXTURE"
# Exercise the canonical tracked-file pipeline in an isolated repository.
git -C "$ARCHIVE_FIXTURE" init -q
git -C "$ARCHIVE_FIXTURE" add --all
create_fixture_archive() {
  local output="$1"
  (
    cd -- "$ARCHIVE_FIXTURE"
    git ls-files -z |
      tar -cf - --null --no-recursion --sort=name --mtime='@0' \
        --owner=0 --group=0 --numeric-owner --format=posix \
        --pax-option=delete=atime,delete=ctime --files-from=- |
      gzip -n >"$output"
  )
}
create_fixture_archive "$ARCHIVE_ONE"
create_fixture_archive "$ARCHIVE_TWO"
cmp -s "$ARCHIVE_ONE" "$ARCHIVE_TWO" || fail 'normalized archives are not byte-identical'
tar -tzf "$ARCHIVE_ONE" >"$CASE_DIR/archive.list"
grep -Fqx 'README.md' "$CASE_DIR/archive.list" || fail 'archive omitted README.md'
grep -Fqx 'manifest.yaml' "$CASE_DIR/archive.list" || fail 'archive omitted manifest.yaml'
grep -Fqx 'ubuntu/config/nvim/init.lua' "$CASE_DIR/archive.list" || fail 'archive omitted Neovim config'
if grep -Eq '(^|/)\.git(/|$)' "$CASE_DIR/archive.list"; then
  fail 'archive included Git metadata'
fi
gzip -cd -- "$ARCHIVE_ONE" >"$CASE_DIR/archive.tar"
# Owner names may legitimately occur in tracked repository URLs. Validate archive
# ownership through tar metadata instead of scanning tracked file payload bytes.
if grep -aFq -- "$CASE_DIR" "$CASE_DIR/archive.tar"; then
  fail 'raw archive leaked a local temporary path'
fi
if tar -tvzf "$ARCHIVE_ONE" | awk '{ print $2 }' | grep -Evqx '0/0'; then
  fail 'archive contains non-normalized owner/group metadata'
fi
mkdir -p "$CASE_DIR/archive-extracted"
tar -xzf "$ARCHIVE_ONE" -C "$CASE_DIR/archive-extracted"
cmp -s "$ROOT/README.md" "$CASE_DIR/archive-extracted/README.md" || fail 'archive extraction changed README.md'
"$CASE_DIR/archive-extracted/tests/sanitize.sh" >"$CASE_DIR/archive-sanitize.out"
pass 'archive pipeline exits zero, is deterministic, extracts, sanitizes, and leaks no local owner metadata'

mkdir -p "$XDG_DATA_HOME/nvim" "$XDG_STATE_HOME/nvim" "$XDG_CACHE_HOME/nvim"
printf 'keep-data\n' >"$XDG_DATA_HOME/nvim/sentinel"
printf 'keep-state\n' >"$XDG_STATE_HOME/nvim/sentinel"
printf 'keep-cache\n' >"$XDG_CACHE_HOME/nvim/sentinel"

# Every managed destination must be preflighted before the first config write.
mkdir -p "$XDG_CONFIG_HOME/atuin" "$XDG_CONFIG_HOME/herdr" "$XDG_CONFIG_HOME/nvim/local"
printf 'original-zsh\n' >"$HOME/.zshrc"
printf 'starship-target\n' >"$XDG_CONFIG_HOME/starship-target.toml"
ln -s -- 'starship-target.toml' "$XDG_CONFIG_HOME/starship.toml"
printf 'original-atuin\n' >"$XDG_CONFIG_HOME/atuin/config.toml"
printf 'original-herdr\n' >"$XDG_CONFIG_HOME/herdr/config.toml"
printf 'original-nvim\n' >"$XDG_CONFIG_HOME/nvim/local/original.lua"
mkfifo "$XDG_CONFIG_HOME/nvim/unsupported.fifo"
if DOTFILES_WORKSTATION_TIMESTAMP=20241231T235959Z \
  "$ROOT/ubuntu/install.sh" --skip-packages --skip-downloads >"$CASE_DIR/preflight-reject.out" 2>&1; then
  fail 'preflight accepted an unsafe Neovim tree'
fi
grep -qx 'original-zsh' "$HOME/.zshrc" || fail 'preflight failure mutated zshrc'
[[ -L "$XDG_CONFIG_HOME/starship.toml" ]] || fail 'preflight failure changed starship symlink type'
[[ "$(readlink -- "$XDG_CONFIG_HOME/starship.toml")" == 'starship-target.toml' ]] || fail 'preflight failure changed starship symlink target'
grep -qx 'original-atuin' "$XDG_CONFIG_HOME/atuin/config.toml" || fail 'preflight failure mutated Atuin config'
grep -qx 'original-herdr' "$XDG_CONFIG_HOME/herdr/config.toml" || fail 'preflight failure mutated Herdr config'
grep -qx 'original-nvim' "$XDG_CONFIG_HOME/nvim/local/original.lua" || fail 'preflight failure mutated Neovim bytes'
[[ -p "$XDG_CONFIG_HOME/nvim/unsupported.fifo" ]] || fail 'preflight failure changed Neovim FIFO type'
assert_not_exists "$HOME/.dotfiles-workstation"
pass 'unsafe Neovim entries fail preflight with zero managed mutation'
rm -rf -- "$HOME/.zshrc" "$XDG_CONFIG_HOME"
mkdir -p "$XDG_CONFIG_HOME"

DOTFILES_WORKSTATION_TIMESTAMP=20250101T000000Z \
  "$ROOT/ubuntu/install.sh" --dry-run --skip-packages --skip-downloads >"$CASE_DIR/dry-run.out"
for contract_line in \
  'Profile: base-config' \
  'APT baseline:' \
  'Recorded Zsh downloads:' \
  'Managed configuration:' \
  'Optional commands:' \
  'Neovim runtime/plugins:'; do
  grep -Fq "$contract_line" "$CASE_DIR/dry-run.out" || fail "dry-run contract section is missing: $contract_line"
done
pass 'dry run names the base-config profile and each installation scope'
assert_not_exists "$HOME/.zshrc"
assert_not_exists "$HOME/.dotfiles-workstation"
assert_not_exists "$XDG_CONFIG_HOME/nvim"
pass 'dry run is immutable'

DOTFILES_WORKSTATION_TIMESTAMP=20250101T000000Z \
  "$ROOT/ubuntu/install.sh" --skip-packages --skip-downloads >"$CASE_DIR/install.out"
assert_file "$HOME/.zshrc"
assert_file "$XDG_CONFIG_HOME/starship.toml"
assert_file "$XDG_CONFIG_HOME/atuin/config.toml"
assert_file "$XDG_CONFIG_HOME/herdr/config.toml"
assert_file "$XDG_CONFIG_HOME/nvim/init.lua"
FIRST_MANIFEST="$HOME/.dotfiles-workstation/backups/20250101T000000Z/manifest.tsv"
assert_file "$FIRST_MANIFEST"
[[ "$(grep -c $'\tabsent\t-\t-' "$FIRST_MANIFEST")" -eq 4 ]] || fail 'first snapshot must record four absent file states'
[[ "$(grep -c $'\tabsent-directory\t-\t-' "$FIRST_MANIFEST")" -eq 1 ]] || fail 'first snapshot must record one absent directory state'
pass 'first install records file and directory absence exactly'

DOTFILES_WORKSTATION_TIMESTAMP=20250101T000000Z \
  "$ROOT/ubuntu/install.sh" --skip-packages --skip-downloads >"$CASE_DIR/reinstall.out"
[[ "$(find "$HOME/.dotfiles-workstation/backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]] || fail 'unchanged install created another snapshot'
pass 'unchanged install is idempotent'

printf '# local customization before replacement\n' >"$HOME/.zshrc"
DOTFILES_WORKSTATION_TIMESTAMP=20250101T000001Z \
  "$ROOT/ubuntu/install.sh" --skip-packages --skip-downloads >"$CASE_DIR/replace.out"
SECOND_MANIFEST="$HOME/.dotfiles-workstation/backups/20250101T000001Z/manifest.tsv"
assert_file "$SECOND_MANIFEST"
[[ "$(grep -c $'\tregular\t' "$SECOND_MANIFEST")" -eq 1 ]] || fail 'changed install must back up one regular file'
assert_file "$HOME/.dotfiles-workstation/backups/20250101T000001Z/files/zshrc"
pass 'changed regular-file bytes receive a scoped backup'

"$ROOT/ubuntu/verify.sh" --home "$HOME" >"$CASE_DIR/verify.out"
pass 'no-network verification accepts installed files and directory'

"$ROOT/ubuntu/rollback.sh" 20250101T000001Z >"$CASE_DIR/rollback-regular.out"
grep -qx '# local customization before replacement' "$HOME/.zshrc" || fail 'rollback did not restore exact prior bytes'
pass 'regular-file rollback restores exact changed bytes only'

cp -- "$ROOT/ubuntu/config/zsh/.zshrc" "$HOME/.zshrc"
printf 'temporary target content\n' >"$XDG_CONFIG_HOME/linked-starship.toml"
ln -sf -- 'linked-starship.toml' "$XDG_CONFIG_HOME/starship.toml"
DOTFILES_WORKSTATION_TIMESTAMP=20250101T000002Z \
  "$ROOT/ubuntu/install.sh" --skip-packages --skip-downloads >"$CASE_DIR/replace-symlink.out"
THIRD_MANIFEST="$HOME/.dotfiles-workstation/backups/20250101T000002Z/manifest.tsv"
expected_target_b64="$(printf '%s' 'linked-starship.toml' | base64 | tr -d '\n')"
grep -Fqx "$XDG_CONFIG_HOME/starship.toml"$'\t'"symlink"$'\t-'$'\t'"$expected_target_b64" "$THIRD_MANIFEST" || fail 'snapshot did not record the symlink target'
rm -f -- "$XDG_CONFIG_HOME/linked-starship.toml"
"$ROOT/ubuntu/rollback.sh" 20250101T000002Z >"$CASE_DIR/rollback-symlink.out"
[[ -L "$XDG_CONFIG_HOME/starship.toml" ]] || fail 'rollback did not restore a symlink object'
[[ "$(readlink -- "$XDG_CONFIG_HOME/starship.toml")" == 'linked-starship.toml' ]] || fail 'rollback changed the captured symlink target'
pass 'symlink rollback restores the exact link target after target removal'

rm -f -- "$XDG_CONFIG_HOME/starship.toml"
cp -- "$ROOT/ubuntu/config/starship.toml" "$XDG_CONFIG_HOME/starship.toml"
rm -rf -- "$XDG_CONFIG_HOME/nvim"
mkdir -p "$XDG_CONFIG_HOME/nvim/lua/local"
printf 'return { portable = false }\n' >"$XDG_CONFIG_HOME/nvim/init.lua"
printf 'local editor state\n' >"$XDG_CONFIG_HOME/nvim/lua/local/settings.lua"
ln -s -- '../init.lua' "$XDG_CONFIG_HOME/nvim/lua/init-link.lua"
DOTFILES_WORKSTATION_TIMESTAMP=20250101T000003Z \
  "$ROOT/ubuntu/install.sh" --skip-packages --skip-downloads >"$CASE_DIR/replace-directory.out"
FOURTH_MANIFEST="$HOME/.dotfiles-workstation/backups/20250101T000003Z/manifest.tsv"
grep -Fqx "$XDG_CONFIG_HOME/nvim"$'\t'"directory"$'\t'"files/nvim"$'\t-' "$FOURTH_MANIFEST" || fail 'snapshot did not record the prior Neovim directory'
assert_file "$HOME/.dotfiles-workstation/backups/20250101T000003Z/files/nvim/lua/local/settings.lua"
"$ROOT/ubuntu/rollback.sh" 20250101T000003Z >"$CASE_DIR/rollback-directory.out"
grep -qx 'return { portable = false }' "$XDG_CONFIG_HOME/nvim/init.lua" || fail 'directory rollback changed prior bytes'
[[ -L "$XDG_CONFIG_HOME/nvim/lua/init-link.lua" ]] || fail 'directory rollback did not restore nested symlink'
[[ "$(readlink -- "$XDG_CONFIG_HOME/nvim/lua/init-link.lua")" == '../init.lua' ]] || fail 'directory rollback changed nested symlink target'
assert_not_exists "$XDG_CONFIG_HOME/nvim/lazy-lock.json"
pass 'directory rollback restores the exact prior tree'

mkfifo "$XDG_CONFIG_HOME/nvim/unsupported.fifo"
if DOTFILES_WORKSTATION_TIMESTAMP=20250101T000004Z \
  "$ROOT/ubuntu/install.sh" --skip-packages --skip-downloads >"$CASE_DIR/special.out" 2>&1; then
  fail 'installer accepted a special entry in the managed directory'
fi
[[ ! -e "$HOME/.dotfiles-workstation/backups/20250101T000004Z" ]] || fail 'unsafe directory created a snapshot before rejection'
rm -f -- "$XDG_CONFIG_HOME/nvim/unsupported.fifo"
pass 'special directory entries are rejected before replacement'

rm -rf -- "$XDG_CONFIG_HOME/nvim"
cp -a -- "$NVIM_SOURCE" "$XDG_CONFIG_HOME/nvim"
"$ROOT/ubuntu/rollback.sh" 20250101T000000Z >"$CASE_DIR/rollback-first.out"
assert_not_exists "$XDG_CONFIG_HOME/nvim"
grep -qx 'keep-data' "$XDG_DATA_HOME/nvim/sentinel"
grep -qx 'keep-state' "$XDG_STATE_HOME/nvim/sentinel"
grep -qx 'keep-cache' "$XDG_CACHE_HOME/nvim/sentinel"
pass 'absent-directory rollback removes only config and preserves all Neovim runtime roots'

printf 'All dotfiles-workstation tests passed; temporary artifacts cleaned by default.\n'
