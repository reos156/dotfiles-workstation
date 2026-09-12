#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"
CASE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-toolchain-tests.XXXXXX")"
trap 'rm -rf -- "$CASE_DIR"' EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_absent() { [[ ! -e "$1" && ! -L "$1" ]] || fail "expected absent path: $1"; }

FIXTURES="$CASE_DIR/fixtures"
STUBS="$CASE_DIR/stubs"
mkdir -p \
  "$FIXTURES/starship-src" \
  "$FIXTURES/node-v22.23.1-linux-x64/bin" \
  "$FIXTURES/node-v22.23.1-linux-x64/lib/node_modules/corepack/dist" \
  "$STUBS"
printf '#!/usr/bin/env sh\necho starship 1.26.0\n' >"$FIXTURES/starship-src/starship"
printf '#!/usr/bin/env sh\necho v22.23.1\n' >"$FIXTURES/node-v22.23.1-linux-x64/bin/node"
printf '#!/usr/bin/env sh\necho npm 10.9.8\n' >"$FIXTURES/node-v22.23.1-linux-x64/bin/npm"
printf '#!/usr/bin/env sh\necho npx 10.9.8\n' >"$FIXTURES/node-v22.23.1-linux-x64/bin/npx"
printf '#!/usr/bin/env sh\necho corepack 0.34.6\n' >"$FIXTURES/node-v22.23.1-linux-x64/lib/node_modules/corepack/dist/corepack.js"
printf '#!/usr/bin/env sh\necho tree-sitter 0.27.0\n' >"$FIXTURES/tree-sitter"
printf '#!/usr/bin/env sh\necho herdr 0.7.5\n' >"$FIXTURES/herdr-linux-x86_64"
printf 'fixture colorls gem\n' >"$FIXTURES/colorls-1.5.0.gem"
chmod +x \
  "$FIXTURES/starship-src/starship" \
  "$FIXTURES/node-v22.23.1-linux-x64/bin/"* \
  "$FIXTURES/node-v22.23.1-linux-x64/lib/node_modules/corepack/dist/corepack.js" \
  "$FIXTURES/tree-sitter" \
  "$FIXTURES/herdr-linux-x86_64"
ln -s ../lib/node_modules/corepack/dist/corepack.js "$FIXTURES/node-v22.23.1-linux-x64/bin/corepack"
tar -czf "$FIXTURES/starship.tar.gz" -C "$FIXTURES/starship-src" starship
tar -cJf "$FIXTURES/node.tar.xz" -C "$FIXTURES" node-v22.23.1-linux-x64
gzip -n -c "$FIXTURES/tree-sitter" >"$FIXTURES/tree-sitter.gz"
starship_sha="$(sha256sum "$FIXTURES/starship.tar.gz" | awk '{print $1}')"
node_sha="$(sha256sum "$FIXTURES/node.tar.xz" | awk '{print $1}')"
herdr_sha="$(sha256sum "$FIXTURES/herdr-linux-x86_64" | awk '{print $1}')"
colorls_sha="$(sha256sum "$FIXTURES/colorls-1.5.0.gem" | awk '{print $1}')"

{
  printf '# name\tversion\turl\tsha256\texpected_member\tformat\tprovenance\n'
  printf 'starship\t1.26.0\thttps://fixtures.invalid/starship.tar.gz\t%s\tstarship\ttar\tpublisher-checksum\n' "$starship_sha"
  printf 'herdr\t0.7.5\thttps://fixtures.invalid/herdr-linux-x86_64\t%s\therdr-linux-x86_64\traw\tpublisher-checksum\n' "$herdr_sha"
  printf 'node\t22.23.1\thttps://fixtures.invalid/node.tar.xz\t%s\tnode-v22.23.1-linux-x64/bin/node\ttree\tpublisher-checksum\n' "$node_sha"
  printf 'colorls\t1.5.0\thttps://fixtures.invalid/colorls-1.5.0.gem\t%s\tcolorls\tgem\tpublisher-checksum\n' "$colorls_sha"
} >"$CASE_DIR/test.lock.tsv"

cat >"$STUBS/sudo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOTFILES_TEST_CALLS/sudo"
STUB
cat >"$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
out=''
url=''
while (($#)); do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  */starship.tar.gz) cp -- "$DOTFILES_TEST_FIXTURES/starship.tar.gz" "$out" ;;
  */herdr-linux-x86_64) cp -- "$DOTFILES_TEST_FIXTURES/herdr-linux-x86_64" "$out" ;;
  */node.tar.xz) cp -- "$DOTFILES_TEST_FIXTURES/node.tar.xz" "$out" ;;
  */colorls-1.5.0.gem) cp -- "$DOTFILES_TEST_FIXTURES/colorls-1.5.0.gem" "$out" ;;
  */tree-sitter-linux-x64.gz) cp -- "$DOTFILES_TEST_FIXTURES/tree-sitter.gz" "$out" ;;
  *) printf 'unexpected URL: %s\n' "$url" >&2; exit 1 ;;
esac
printf '%s\n' "$url" >>"$DOTFILES_TEST_CALLS/curl"
STUB
cat >"$STUBS/gem" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOTFILES_TEST_CALLS/gem"
install_dir=''
bin_dir=''
artifact="${@: -1}"
while (($#)); do
  case "$1" in
    --install-dir) install_dir="$2"; shift 2 ;;
    --bindir) bin_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ "$artifact" == *.gem ]] || { printf 'Could not find a valid gem %s\n' "$artifact" >&2; exit 1; }
[[ "$install_dir" == "$HOME/.local/share/dotfiles-workstation/tools/colorls/"* ]] || { printf 'gem install escaped user-local tool root: %s\n' "$install_dir" >&2; exit 1; }
[[ "$bin_dir" == "$HOME/.local/share/dotfiles-workstation/tools/colorls/"* ]] || { printf 'gem bindir escaped user-local tool root: %s\n' "$bin_dir" >&2; exit 1; }
mkdir -p "$install_dir" "$bin_dir"
cat >"$bin_dir/colorls" <<'LAUNCHER'
#!/usr/bin/env bash
[[ "${GEM_HOME:-}" == */gems ]] || { printf 'missing pinned GEM_HOME\n' >&2; exit 71; }
[[ "${GEM_PATH:-}" == "$GEM_HOME" ]] || { printf 'missing pinned GEM_PATH\n' >&2; exit 72; }
printf 'colorls 1.5.0'
printf ' <%s>' "$@"
printf '\n'
LAUNCHER
chmod 0755 "$bin_dir/colorls"
STUB
cat >"$STUBS/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == clone ]]; then
  destination="${@: -1}"
  url="${@: -2:1}"
  mkdir -p "$destination/.git"
  printf '%s\n' "$url" >"$destination/.git/test-origin"
  printf '%s\n' "$*" >>"$DOTFILES_TEST_CALLS/git"
  exit 0
fi
if [[ "$1" == -C ]]; then
  directory="$2"
  if [[ "$3" == remote && "$4" == get-url && "$5" == origin ]]; then
    cat "$directory/.git/test-origin"
  elif [[ "$3" == rev-parse && "$4" == HEAD && "$directory" == *lazy.nvim* ]]; then
    printf '%s\n' 85c7ff3711b730b4030d03144f6db6375044ae82
  elif [[ "$3" == rev-parse ]]; then
    printf '%s\n' recorded-test-revision
  fi
  exit 0
fi
exit 1
STUB
cat >"$STUBS/nvim" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOTFILES_TEST_CALLS/nvim"
printf 'RUNTIME_BOOTSTRAP_OK\n'
STUB
cat >"$STUBS/check-runtime" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOTFILES_TEST_CALLS/check-runtime"
STUB
chmod +x "$STUBS/"*

new_home() {
  local name="$1"
  export HOME="$CASE_DIR/$name/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export DOTFILES_TEST_CALLS="$CASE_DIR/$name/calls"
  export DOTFILES_TEST_FIXTURES="$FIXTURES"
  export DOTFILES_RUNTIME_CHECK="$STUBS/check-runtime"
  export RUNTIME_TEST_TREE_GZIP="$FIXTURES/tree-sitter.gz"
  export DOTFILES_WORKSTATION_TEST_MODE=1
  export DOTFILES_WORKSTATION_TEST_OS_ID=ubuntu
  export DOTFILES_WORKSTATION_TEST_OS_VERSION=26.04
  export DOTFILES_WORKSTATION_TEST_ARCH=x86_64
  export DOTFILES_WORKSTATION_TOOLCHAIN_LOCK="$CASE_DIR/test.lock.tsv"
  mkdir -p "$HOME" "$DOTFILES_TEST_CALLS"
}

new_home approval
if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain >"$CASE_DIR/approval.out" 2>&1; then
  fail 'source-toolchain accepted missing approvals'
fi
grep -Fq -- '--approve-packages, --approve-downloads, and --approve-runtime-bootstrap' "$CASE_DIR/approval.out" || fail 'approval failure was not actionable'
assert_absent "$HOME/.zshrc"
assert_absent "$XDG_DATA_HOME/dotfiles-workstation"
pass 'source-toolchain rejects missing approvals before mutation'

new_home unsupported
export DOTFILES_WORKSTATION_TEST_ARCH=aarch64
if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/unsupported.out" 2>&1; then
  fail 'source-toolchain accepted an unsupported architecture'
fi
grep -Fq 'Ubuntu 26.04 Linux x86_64' "$CASE_DIR/unsupported.out" || fail 'unsupported-platform message omits the supported boundary'
assert_absent "$HOME/.zshrc"
pass 'source-toolchain rejects unsupported platforms before mutation'

new_home dry
PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --dry-run >"$CASE_DIR/dry.out"
for expected in \
  'Profile: source-toolchain' \
  'Ubuntu 26.04 Linux x86_64 only' \
  'build-essential' \
  'starship 1.26.0' \
  'node 22.23.1' \
  "$XDG_DATA_HOME/dotfiles-workstation/tools" \
  "$HOME/.local/bin" \
  'Runtime bootstrap: deferred to unit3'; do
  grep -Fq "$expected" "$CASE_DIR/dry.out" || fail "dry-run contract omitted: $expected"
done
assert_absent "$HOME/.zshrc"
assert_absent "$XDG_DATA_HOME/dotfiles-workstation"
[[ ! -s "$DOTFILES_TEST_CALLS/sudo" && ! -s "$DOTFILES_TEST_CALLS/curl" ]] || fail 'dry run invoked package or network stubs'
pass 'source-toolchain dry run is exact and immutable'

new_home skip
for flag in --skip-packages --skip-downloads; do
  if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap "$flag" >"$CASE_DIR/skip.out" 2>&1; then
    fail "source-toolchain silently accepted $flag"
  fi
  grep -Fq 'does not accept --skip-packages or --skip-downloads' "$CASE_DIR/skip.out" || fail 'skip rejection was not explicit'
done
pass 'source-toolchain refuses silent prerequisite skips'

new_home install
PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/install.out"
TOOLS="$XDG_DATA_HOME/dotfiles-workstation/tools"
[[ -x "$TOOLS/starship/1.26.0/starship" ]] || fail 'starship version artifact missing'
[[ -x "$TOOLS/herdr/0.7.5/herdr" ]] || fail 'raw Herdr artifact was not normalized to its activated command name'
[[ -x "$TOOLS/colorls/1.5.0/bin/colorls" ]] || fail 'colorls gem executable missing'
grep -Eq -- '--install-dir [^ ]+ --bindir [^ ]+ --no-document [^ ]+/colorls\.gem$' "$DOTFILES_TEST_CALLS/gem" || fail 'colorls gem was not installed from an explicit .gem staging filename'
[[ -L "$HOME/.local/bin/colorls" ]] || fail 'colorls activation missing'
[[ "$(readlink "$HOME/.local/bin/colorls")" == "$TOOLS/colorls/1.5.0/activation/colorls" ]] || fail 'wrong colorls activation target'
colorls_output="$(env -u GEM_HOME -u GEM_PATH "$HOME/.local/bin/colorls" '--quoted arg' 'literal*value')" || fail 'colorls wrapper could not discover its pinned gem home'
[[ "$colorls_output" == 'colorls 1.5.0 <--quoted arg> <literal*value>' ]] || fail 'colorls wrapper did not preserve arguments safely'
if grep -Eq '(^|[[:space:]])(gem|colorls)([[:space:]]|$)' "$DOTFILES_TEST_CALLS/sudo"; then
  fail 'colorls gem installation used sudo'
fi
[[ -L "$HOME/.local/bin/herdr" ]] || fail 'Herdr activation missing'
[[ "$(readlink "$HOME/.local/bin/herdr")" == "$TOOLS/herdr/0.7.5/herdr" ]] || fail 'wrong Herdr activation target'
for command in node npm npx; do
  [[ -L "$HOME/.local/bin/$command" ]] || fail "missing Node activation: $command"
  [[ "$(readlink "$HOME/.local/bin/$command")" == "$TOOLS/node/22.23.1/bin/$command" ]] || fail "wrong Node activation target: $command"
done
[[ -L "$HOME/.local/bin/starship" ]] || fail 'starship activation missing'
[[ -L "$TOOLS/node/22.23.1/bin/corepack" ]] || fail 'Node-style nested Corepack symlink was not preserved'
[[ "$(readlink "$TOOLS/node/22.23.1/bin/corepack")" == ../lib/node_modules/corepack/dist/corepack.js ]] || fail 'Node-style nested Corepack symlink target changed'
[[ -x "$TOOLS/node/22.23.1/bin/corepack" ]] || fail 'Node-style nested Corepack symlink does not resolve to an executable member'
[[ -f "$TOOLS/starship/1.26.0/.installed.tsv" && -f "$TOOLS/node/22.23.1/.installed.tsv" ]] || fail 'artifact markers missing'
pass 'verified archives install safe internal relative symlinks and activate every Node binary'

curl_count="$(wc -l <"$DOTFILES_TEST_CALLS/curl")"
PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/idempotent.out"
[[ "$(wc -l <"$DOTFILES_TEST_CALLS/curl")" -eq "$curl_count" ]] || fail 'idempotent install downloaded assets again'
grep -Fq 'already verified and active' "$CASE_DIR/idempotent.out" || fail 'idempotent result was not reported'
pass 'idempotence verifies markers, artifacts, and active links'

new_home checksum
sed "s/$starship_sha/$(printf '0%.0s' {1..64})/" "$CASE_DIR/test.lock.tsv" >"$CASE_DIR/bad-checksum.lock.tsv"
export DOTFILES_WORKSTATION_TOOLCHAIN_LOCK="$CASE_DIR/bad-checksum.lock.tsv"
if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/checksum.out" 2>&1; then
  fail 'checksum mismatch was accepted'
fi
grep -Fq 'SHA256 mismatch' "$CASE_DIR/checksum.out" || fail 'checksum failure was not explicit'
assert_absent "$XDG_DATA_HOME/dotfiles-workstation/tools/starship/1.26.0"
[[ -z "$(find "$XDG_DATA_HOME/dotfiles-workstation/tools/starship" -maxdepth 1 -name '.*.staging.*' -print -quit 2>/dev/null)" ]] || fail 'checksum failure left staging content'
pass 'checksum mismatch cleans staging and leaves no installed version'

new_home raw-checksum
sed "s/$herdr_sha/$(printf '0%.0s' {1..64})/" "$CASE_DIR/test.lock.tsv" >"$CASE_DIR/bad-raw-checksum.lock.tsv"
export DOTFILES_WORKSTATION_TOOLCHAIN_LOCK="$CASE_DIR/bad-raw-checksum.lock.tsv"
if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/raw-checksum.out" 2>&1; then
  fail 'raw executable checksum mismatch was accepted'
fi
grep -Fq 'SHA256 mismatch for herdr 0.7.5' "$CASE_DIR/raw-checksum.out" || fail 'raw checksum failure was not explicit'
assert_absent "$XDG_DATA_HOME/dotfiles-workstation/tools/herdr/0.7.5"
[[ -z "$(find "$XDG_DATA_HOME/dotfiles-workstation/tools/herdr" -maxdepth 1 -name '.*.staging.*' -print -quit 2>/dev/null)" ]] || fail 'raw checksum failure left staging content'
pass 'raw executable checksum mismatch cleans staging and leaves no installed version'

new_home gem-checksum
sed "s/$colorls_sha/$(printf '0%.0s' {1..64})/" "$CASE_DIR/test.lock.tsv" >"$CASE_DIR/bad-gem-checksum.lock.tsv"
export DOTFILES_WORKSTATION_TOOLCHAIN_LOCK="$CASE_DIR/bad-gem-checksum.lock.tsv"
if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/gem-checksum.out" 2>&1; then
  fail 'gem checksum mismatch was accepted'
fi
grep -Fq 'SHA256 mismatch for colorls 1.5.0' "$CASE_DIR/gem-checksum.out" || fail 'gem checksum failure was not explicit'
[[ ! -s "$DOTFILES_TEST_CALLS/gem" ]] || fail 'gem install ran before checksum verification'
assert_absent "$XDG_DATA_HOME/dotfiles-workstation/tools/colorls/1.5.0"
[[ -z "$(find "$XDG_DATA_HOME/dotfiles-workstation/tools/colorls" -maxdepth 1 -name '.*.staging.*' -print -quit 2>/dev/null)" ]] || fail 'gem checksum failure left staging content'
pass 'gem checksum mismatch prevents installation and cleans staging'

new_home raw-member
sed $'s/herdr-linux-x86_64\traw/..\\/herdr\traw/' "$CASE_DIR/test.lock.tsv" >"$CASE_DIR/unsafe-raw-member.lock.tsv"
export DOTFILES_WORKSTATION_TOOLCHAIN_LOCK="$CASE_DIR/unsafe-raw-member.lock.tsv"
if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/raw-member.out" 2>&1; then
  fail 'unsafe raw executable member was accepted'
fi
grep -Fq 'Invalid raw executable name for herdr: ../herdr' "$CASE_DIR/raw-member.out" || fail 'unsafe raw member failure was not explicit'
assert_absent "$XDG_DATA_HOME/dotfiles-workstation/tools/herdr/0.7.5"
assert_absent "$XDG_DATA_HOME/dotfiles-workstation/tools/herdr/herdr"
[[ -z "$(find "$XDG_DATA_HOME/dotfiles-workstation/tools/herdr" -maxdepth 1 -name '.*.staging.*' -print -quit 2>/dev/null)" ]] || fail 'unsafe raw member failure left staging content'
pass 'raw executable member paths are rejected without escape or half-install'

mkdir -p "$FIXTURES/unsafe-src"
printf 'escape\n' >"$FIXTURES/unsafe-src/payload"
tar -czf "$FIXTURES/starship.tar.gz" -C "$FIXTURES/unsafe-src" --transform='s|payload|../escape|' payload
unsafe_sha="$(sha256sum "$FIXTURES/starship.tar.gz" | awk '{print $1}')"
sed "s/$starship_sha/$unsafe_sha/" "$CASE_DIR/test.lock.tsv" >"$CASE_DIR/unsafe.lock.tsv"
new_home unsafe
export DOTFILES_WORKSTATION_TOOLCHAIN_LOCK="$CASE_DIR/unsafe.lock.tsv"
if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/unsafe.out" 2>&1; then
  fail 'unsafe archive was accepted'
fi
grep -Fq 'Unsafe archive member' "$CASE_DIR/unsafe.out" || fail 'unsafe archive failure was not explicit'
assert_absent "$CASE_DIR/unsafe/escape"
assert_absent "$XDG_DATA_HOME/dotfiles-workstation/tools/starship/1.26.0"
[[ -z "$(find "$XDG_DATA_HOME/dotfiles-workstation/tools/starship" -maxdepth 1 -name '.*.staging.*' -print -quit 2>/dev/null)" ]] || fail 'unsafe archive failure left staging content'
pass 'unsafe archive paths are rejected without escape, staging, or half-install'

# Restore the valid Starship fixture before isolating Node archive failures.
tar -czf "$FIXTURES/starship.tar.gz" -C "$FIXTURES/starship-src" starship

make_unsafe_node_link_archive() {
  local link_target="$1"
  python3 - "$FIXTURES/node.tar.xz" "$link_target" <<'PY'
import io, sys, tarfile

archive, target = sys.argv[1:]
root = "node-v22.23.1-linux-x64"
with tarfile.open(archive, "w:xz") as tf:
    executable = b"#!/usr/bin/env sh\necho v22.23.1\n"
    node = tarfile.TarInfo(f"{root}/bin/node")
    node.mode = 0o755
    node.size = len(executable)
    tf.addfile(node, io.BytesIO(executable))
    link = tarfile.TarInfo(f"{root}/bin/corepack")
    link.type = tarfile.SYMTYPE
    link.linkname = target
    tf.addfile(link)
PY
}

for link_case in escaping absolute empty; do
  case "$link_case" in
    escaping)
      link_target='../../../outside-corepack'
      expected_error='Unsafe archive member link'
      ;;
    absolute)
      link_target='/tmp/outside-corepack'
      expected_error='Unsafe archive member link'
      ;;
    empty)
      link_target=''
      expected_error='Unsafe archive member link'
      ;;
  esac
  make_unsafe_node_link_archive "$link_target"
  unsafe_node_sha="$(sha256sum "$FIXTURES/node.tar.xz" | awk '{print $1}')"
  sed "s/$node_sha/$unsafe_node_sha/" "$CASE_DIR/test.lock.tsv" >"$CASE_DIR/unsafe-node-$link_case.lock.tsv"
  new_home "unsafe-node-$link_case"
  export DOTFILES_WORKSTATION_TOOLCHAIN_LOCK="$CASE_DIR/unsafe-node-$link_case.lock.tsv"
  if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/unsafe-node-$link_case.out" 2>&1; then
    fail "unsafe $link_case archive symlink was accepted"
  fi
  grep -Fq "$expected_error" "$CASE_DIR/unsafe-node-$link_case.out" || fail "unsafe $link_case archive symlink failure was not explicit"
  assert_absent "$CASE_DIR/unsafe-node-$link_case/outside-corepack"
  assert_absent "$XDG_DATA_HOME/dotfiles-workstation/tools/node/22.23.1"
  [[ -z "$(find "$XDG_DATA_HOME/dotfiles-workstation/tools/node" -maxdepth 1 -name '.*.staging.*' -print -quit 2>/dev/null)" ]] || fail "unsafe $link_case archive symlink left staging content"
  pass "unsafe $link_case archive symlink is rejected without escape, staging, or half-install"
done

# Restore the valid Node fixture for the activation-conflict case.
tar -cJf "$FIXTURES/node.tar.xz" -C "$FIXTURES" node-v22.23.1-linux-x64
new_home conflict
mkdir -p "$HOME/.local/bin"
printf 'unowned\n' >"$HOME/.local/bin/herdr"
if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/conflict.out" 2>&1; then
  fail 'unowned activation destination was overwritten'
fi
grep -Fq 'Refusing unowned activation destination' "$CASE_DIR/conflict.out" || fail 'activation conflict was not explicit'
grep -qx 'unowned' "$HOME/.local/bin/herdr" || fail 'activation conflict changed unowned bytes'
pass 'unowned raw executable activation destinations are preserved'

new_home gem-conflict
mkdir -p "$HOME/.local/bin"
printf 'unowned colorls\n' >"$HOME/.local/bin/colorls"
if PATH="$STUBS:$PATH" "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads --approve-runtime-bootstrap >"$CASE_DIR/gem-conflict.out" 2>&1; then
  fail 'unowned colorls activation destination was overwritten'
fi
grep -Fq 'Refusing unowned activation destination' "$CASE_DIR/gem-conflict.out" || fail 'colorls activation conflict was not explicit'
grep -qx 'unowned colorls' "$HOME/.local/bin/colorls" || fail 'colorls activation conflict changed unowned bytes'
[[ -x "$XDG_DATA_HOME/dotfiles-workstation/tools/colorls/1.5.0/bin/colorls" ]] || fail 'verified colorls install was not retained after activation conflict'
pass 'unowned colorls activation destination is preserved without system gem mutation'

printf 'All source-toolchain installer tests passed.\n'
