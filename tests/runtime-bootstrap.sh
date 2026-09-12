#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"
REAL_NVIM="$(command -v nvim 2>/dev/null || true)"
REAL_LUA="$(command -v lua 2>/dev/null || command -v luajit 2>/dev/null || true)"
CASE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-runtime-bootstrap-test.XXXXXX")"
cleanup() { rm -rf -- "$CASE_DIR"; }
trap cleanup EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "missing '$2' in ${1##*/}"; }

export HOME="$CASE_DIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export DOTFILES_WORKSTATION_TEST_MODE=1
export DOTFILES_WORKSTATION_TEST_OS_ID=ubuntu
export DOTFILES_WORKSTATION_TEST_OS_VERSION=26.04
export DOTFILES_WORKSTATION_TEST_ARCH=x86_64
mkdir -p "$HOME" "$CASE_DIR/bin"
export PATH="$CASE_DIR/bin:/usr/bin:/bin"
COMMAND_LOG="$CASE_DIR/commands.log"
export RUNTIME_TEST_LOG="$COMMAND_LOG"

cat >"$CASE_DIR/bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$RUNTIME_TEST_LOG"
exit 90
STUB
chmod +x "$CASE_DIR/bin/sudo"

if "$ROOT/ubuntu/install.sh" --profile source-toolchain --approve-packages --approve-downloads >"$CASE_DIR/missing-runtime.out" 2>&1; then
  fail 'source-toolchain accepted missing runtime bootstrap approval'
fi
[[ ! -s "$COMMAND_LOG" ]] || fail 'missing approval reached an install mutation'
assert_contains "$CASE_DIR/missing-runtime.out" '--approve-runtime-bootstrap'
pass 'all source-toolchain approvals are rejected before mutation'

"$ROOT/ubuntu/install.sh" --profile source-toolchain --dry-run >"$CASE_DIR/dry-run.out"
assert_contains "$CASE_DIR/dry-run.out" 'Pinned Neovim runtime bootstrap:'
[[ ! -s "$COMMAND_LOG" ]] || fail 'dry run executed an external mutation'
pass 'dry run reports runtime scope without bootstrap or network'

# Runtime-bootstrap unit stubs: no real HOME, network, npm, apt, or Neovim is used.
LAZY_COMMIT='85c7ff3711b730b4030d03144f6db6375044ae82'
cat >"$CASE_DIR/bin/git" <<STUB
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >>"\$RUNTIME_TEST_LOG"
case "\$*" in
  *clone*) destination="\${!#}"; mkdir -p "\$destination/.git" ;;
  *'rev-parse HEAD'*) printf '%s\n' '$LAZY_COMMIT' ;;
esac
STUB
cat >"$CASE_DIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$RUNTIME_TEST_LOG"
out=''
while (($#)); do [[ "$1" == -o ]] && { out="$2"; break; }; shift; done
[[ -n "$out" ]] || exit 2
cp -- "$RUNTIME_TEST_TREE_GZIP" "$out"
STUB
cat >"$CASE_DIR/bin/nvim" <<'STUB'
#!/usr/bin/env bash
printf 'nvim %s\n' "$*" >>"$RUNTIME_TEST_LOG"
if [[ -n "${RUNTIME_TEST_NVIM_SLEEP:-}" ]]; then sleep "$RUNTIME_TEST_NVIM_SLEEP"; fi
printf '%s\n' "${RUNTIME_TEST_NVIM_OUTPUT:-RUNTIME_BOOTSTRAP_OK}"
exit "${RUNTIME_TEST_NVIM_STATUS:-0}"
STUB
cat >"$CASE_DIR/bin/npm" <<'STUB'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >>"$RUNTIME_TEST_LOG"
exit 0
STUB
cat >"$CASE_DIR/check-runtime" <<'STUB'
#!/usr/bin/env bash
printf 'check-runtime %s\n' "$*" >>"$RUNTIME_TEST_LOG"
exit 0
STUB
chmod +x "$CASE_DIR/bin/git" "$CASE_DIR/bin/curl" "$CASE_DIR/bin/nvim" "$CASE_DIR/bin/npm" "$CASE_DIR/check-runtime"
printf '#!/usr/bin/env bash\nprintf "tree-sitter 0.27.0\\n"\n' >"$CASE_DIR/tree-sitter"
gzip -n -c "$CASE_DIR/tree-sitter" >"$CASE_DIR/tree-sitter.gz"
export RUNTIME_TEST_TREE_GZIP="$CASE_DIR/tree-sitter.gz"
export DOTFILES_RUNTIME_CHECK="$CASE_DIR/check-runtime"

mkdir -p "$XDG_CONFIG_HOME/nvim"
cp -- "$ROOT/ubuntu/config/nvim/lazy-lock.json" "$XDG_CONFIG_HOME/nvim/lazy-lock.json"
lock_before="$(sha256sum "$XDG_CONFIG_HOME/nvim/lazy-lock.json")"
if "$ROOT/ubuntu/lib/runtime-bootstrap.sh" >"$CASE_DIR/helper-missing-approval.out" 2>&1; then
  fail 'runtime bootstrap helper accepted missing approval'
fi
[[ "$lock_before" == "$(sha256sum "$XDG_CONFIG_HOME/nvim/lazy-lock.json")" ]] || fail 'approval rejection changed the managed Lazy lock'
[[ ! -s "$COMMAND_LOG" ]] || fail 'approval rejection reached a runtime mutation'
assert_contains "$CASE_DIR/helper-missing-approval.out" '--approve-runtime-bootstrap'
pass 'runtime bootstrap helper rejects missing approval before mutation'

TREE_CONFLICT="$XDG_DATA_HOME/dotfiles-workstation/runtime/tree-sitter/0.27.0"
mkdir -p "$TREE_CONFLICT"
printf 'unmanaged\n' >"$TREE_CONFLICT/conflict"
if "$ROOT/ubuntu/lib/runtime-bootstrap.sh" --approve-runtime-bootstrap >"$CASE_DIR/runtime-conflict.out" 2>&1; then
  fail 'runtime bootstrap accepted a conflicting tree-sitter destination'
fi
[[ ! -s "$COMMAND_LOG" ]] || fail 'runtime destination preflight failed after a mutation'
[[ ! -e "$XDG_DATA_HOME/nvim/lazy/lazy.nvim" ]] || fail 'runtime destination preflight created lazy.nvim before rejection'
rm -rf -- "$TREE_CONFLICT"
pass 'all runtime destinations are preflighted before mutation'

"$ROOT/ubuntu/lib/runtime-bootstrap.sh" --approve-runtime-bootstrap >"$CASE_DIR/bootstrap.out"
[[ "$lock_before" == "$(sha256sum "$XDG_CONFIG_HOME/nvim/lazy-lock.json")" ]] || fail 'runtime bootstrap changed the managed Lazy lock'
assert_contains "$COMMAND_LOG" "checkout --detach $LAZY_COMMIT"
assert_contains "$COMMAND_LOG" 'curl --fail --location'
assert_contains "$COMMAND_LOG" 'runtime-bootstrap.lua'
assert_contains "$ROOT/ubuntu/runtime-bootstrap.lua" 'require("mason").setup'
assert_contains "$ROOT/ubuntu/runtime-bootstrap.lua" 'require("nvim-treesitter").install'
if grep -Fq 'require("nvim-treesitter.install")' "$ROOT/ubuntu/runtime-bootstrap.lua"; then
  fail 'runtime bootstrap uses the nvim-treesitter internal install module'
fi
assert_contains "$ROOT/ubuntu/lib/runtime-bootstrap.sh" 'timeout --signal=TERM --kill-after='
assert_contains "$ROOT/ubuntu/runtime-bootstrap.lua" 'RUNTIME_BOOTSTRAP_MARKSMAN_ICU'
assert_contains "$ROOT/ubuntu/runtime-bootstrap.lua" '@biomejs/cli-linux-x64@2.5.12'
assert_contains "$ROOT/ubuntu/runtime-bootstrap.lua" "vim.treesitter.query.get"
pass 'bootstrap pins Lazy and tree-sitter CLI, waits, and delegates deterministic Lua orchestration'

if [[ -n "$REAL_NVIM" ]]; then
  "$REAL_NVIM" --headless -u NONE -i NONE \
    --cmd "lua assert(loadfile([=[$ROOT/ubuntu/runtime-bootstrap.lua]=]))" +qa >/dev/null
  pass 'real Neovim headless parses the runtime orchestrator offline'
fi

# Exercise the Mason install-handle contract without a real plugin install or network.
MASON_HARNESS="$CASE_DIR/mason-harness.lua"
cat >"$MASON_HARNESS" <<'LUA'
local scenario = assert(os.getenv("RUNTIME_MASON_SCENARIO"))
local runtime_script = assert(os.getenv("RUNTIME_MASON_SCRIPT"))
local runtime_lock = assert(os.getenv("RUNTIME_MASON_LOCK"))
local operation_log = assert(os.getenv("RUNTIME_MASON_LOG"))
local real_open = io.open
local installed = {}
local pending = {}

local function log(line)
  local handle = assert(real_open(operation_log, "a"))
  handle:write(line, "\n")
  handle:close()
end

io.open = function(path, mode)
  local package_name = path:match("/mason/packages/([^/]+)/mason%-receipt%.json$")
  if package_name then
    if not installed[package_name] then return nil, "missing receipt" end
    local handle = {}
    function handle:read() return "receipt:" .. package_name end
    function handle:close() end
    return handle
  end
  if path:match("/lazy%-lock%.json$") then
    local handle = {}
    function handle:read() return "lazy-lock" end
    function handle:close() end
    return handle
  end
  return real_open(path, mode)
end

local source_prefixes = {
  ["angular-language-server"] = "pkg:npm/%40angular/language-server@",
  ["biome"] = "pkg:npm/%40biomejs/biome@",
  ["eslint-lsp"] = "pkg:npm/vscode-langservers-extracted@",
  ["json-lsp"] = "pkg:npm/vscode-langservers-extracted@",
  ["lua-language-server"] = "pkg:github/luals/lua-language-server@",
  ["markdown-toc"] = "pkg:npm/markdown-toc@",
  ["markdownlint-cli2"] = "pkg:npm/markdownlint-cli2@",
  ["marksman"] = "pkg:github/artempyanykh/marksman@",
  ["prettier"] = "pkg:npm/prettier@",
  ["shfmt"] = "pkg:github/mvdan/sh@",
  ["stylua"] = "pkg:github/johnnymorganz/stylua@",
}
local versions = {}
for line in assert(real_open(runtime_lock, "r")):lines() do
  local kind, name, version = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)")
  if kind == "mason" then versions[name] = version end
end
if scenario == "registry-changed" or scenario == "wrong-package" or scenario == "wrong-source-package" or scenario == "wrong-version" then
  for name in pairs(versions) do installed[name] = true end
end

vim = {
  env = {
    DOTFILES_RUNTIME_LOCK = runtime_lock,
    DOTFILES_RUNTIME_LAZY_COMMIT = "85c7ff3711b730b4030d03144f6db6375044ae82",
  },
  fn = {
    stdpath = function(kind)
      if kind == "data" then return "/test-data" end
      if kind == "config" then return "/test-config" end
      error("unexpected stdpath: " .. kind)
    end,
    isdirectory = function() return 1 end,
    executable = function(path)
      if scenario == "biome-executable-missing" and path:match("/biome$") then return 0 end
      if scenario == "angular-executable-missing" and path:match("/ngserver$") then return 0 end
      return 1
    end,
    filereadable = function() return 1 end,
  },
  json = {
    decode = function(contents)
      if contents == "lazy-lock" then
        return { ["lazy.nvim"] = { commit = "85c7ff3711b730b4030d03144f6db6375044ae82" } }
      end
      local name = assert(contents:match("^receipt:(.+)$"))
      local receipt_name = name
      local source_prefix = assert(source_prefixes[name])
      local source_version = assert(versions[name])
      if scenario == "wrong-package" and name == "angular-language-server" then
        receipt_name = "typescript-language-server"
      elseif scenario == "wrong-source-package" and name == "angular-language-server" then
        source_prefix = "pkg:npm/not-angular-language-server@"
      elseif scenario == "wrong-version" and name == "angular-language-server" then
        source_version = "0.0.0"
      end
      local receipt = {
        name = receipt_name,
        source = { id = source_prefix .. source_version },
      }
      if scenario == "registry-changed" then
        receipt.registry = {
          version = "evolving-official-release",
          checksums = {
            ["registry.json.zip"] = string.rep("1", 64),
            ["registry.json"] = string.rep("2", 64),
          },
        }
      end
      return receipt
    end,
  },
  system = function()
    return { wait = function() return { code = 0, stdout = "ok", stderr = "" } end }
  end,
  wait = function(timeout, predicate)
    log("wait " .. tostring(timeout))
    for _ = 1, 20 do
      if predicate() then return true end
      local callback = table.remove(pending, 1)
      if callback then callback() end
    end
    return predicate()
  end,
  trim = function(value) return (value:gsub("^%s+", ""):gsub("%s+$", "")) end,
  treesitter = { query = { get = function() return {} end } },
  cmd = function(command)
    if command == "qa" then os.exit(0) end
    if command == "cquit 1" then os.exit(1) end
    error("unexpected vim command: " .. command)
  end,
}

package.preload["lazy"] = function()
  return { restore = function() end, load = function() end }
end
package.preload["lazy.core.config"] = function() return { plugins = {} } end
package.preload["mason"] = function()
  return {
    setup = function(options)
      assert(#options.registries == 1 and options.registries[1] == "github:mason-org/mason-registry")
    end,
  }
end
package.preload["mason-registry"] = function()
  return {
    refresh = function(callback) callback(true) end,
    get_package = function(name)
      return {
        install = function(_, options, install_callback)
          assert(options.version == versions[name] and options.force == true)
          assert(type(install_callback) == "function", "Mason install callback is required")
          log("install " .. name)
          local handle = { closed = false, aborted = false, close_callback = nil }
          function handle:is_closed() return self.closed end
          function handle:is_cancelled() return self.aborted end
          function handle:once(event, callback)
            assert(event == "closed", "unexpected install event: " .. tostring(event))
            self.close_callback = callback
          end

          if not (scenario == "timeout" and name == "markdown-toc") then
            table.insert(pending, function()
              if scenario == "callback-absent" and name == "markdown-toc" then
                handle.closed = true
                handle.close_callback()
              elseif scenario == "closed-mismatch" and name == "markdown-toc" then
                install_callback(true)
              elseif scenario == "markdown-failure" and name == "markdown-toc" then
                install_callback(false, { message = "wget exited with status 8" })
                handle.closed = true
                handle.close_callback()
              elseif scenario == "secret-failure" and name == "markdown-toc" then
                local sensitive_fixture = "download failed?to" .. "ken=" .. "do-" .. "not-print"
                install_callback(false, { message = sensitive_fixture })
                handle.closed = true
                handle.close_callback()
              elseif scenario == "markdown-aborted" and name == "markdown-toc" then
                handle.aborted = true
                install_callback(false, { reason = "installation aborted" })
                handle.closed = true
                handle.close_callback()
              else
                if not (scenario == "biome-receipt-missing" and name == "biome") then installed[name] = true end
                if scenario == "biome-warning" and name == "biome" then
                  install_callback(true, { message = "benign schema warning" })
                else
                  install_callback(true)
                end
                handle.closed = true
                handle.close_callback()
              end
            end)
          end
          return handle
        end,
      }
    end,
  }
end
package.preload["nvim-treesitter"] = function()
  return { install = function() return { wait = function() return true end } end }
end

assert(loadfile(runtime_script))()
LUA

run_mason_case() {
  local scenario="$1" output="$2" log_file="$3"
  : >"$log_file"
  if [[ -n "$REAL_LUA" ]]; then
    RUNTIME_MASON_SCENARIO="$scenario" RUNTIME_MASON_SCRIPT="$ROOT/ubuntu/runtime-bootstrap.lua" \
      RUNTIME_MASON_LOCK="$ROOT/ubuntu/runtime.lock.tsv" RUNTIME_MASON_LOG="$log_file" \
      "$REAL_LUA" "$MASON_HARNESS" >"$output" 2>&1
  elif [[ -n "$REAL_NVIM" ]]; then
    RUNTIME_MASON_SCENARIO="$scenario" RUNTIME_MASON_SCRIPT="$ROOT/ubuntu/runtime-bootstrap.lua" \
      RUNTIME_MASON_LOCK="$ROOT/ubuntu/runtime.lock.tsv" RUNTIME_MASON_LOG="$log_file" \
      "$REAL_NVIM" --headless -u NONE -i NONE -l "$MASON_HARNESS" >"$output" 2>&1
  else
    fail 'Mason API contract tests require Lua or Neovim'
  fi
}

if ! run_mason_case success "$CASE_DIR/mason-success.out" "$CASE_DIR/mason-success.log"; then
  fail 'closed-success Mason handles did not complete promptly'
fi
[[ "$(grep -c '^install ' "$CASE_DIR/mason-success.log")" -eq 11 ]] || fail 'not all Mason package rows installed once'
[[ "$(sed -n 's/^install //p' "$CASE_DIR/mason-success.log" | sort -u | wc -l)" -eq 11 ]] || fail 'a Mason package row installed more than once'
assert_contains "$CASE_DIR/mason-success.out" 'RUNTIME_BOOTSTRAP_OK'
pass 'all Mason rows advance once on closed-success handles'

if ! run_mason_case registry-changed "$CASE_DIR/mason-registry-changed.out" "$CASE_DIR/mason-registry-changed.log"; then
  fail 'matching Mason package receipts were rejected after the official registry evolved'
fi
if grep -q '^install ' "$CASE_DIR/mason-registry-changed.log"; then fail 'registry metadata change reinstalled matching Mason package versions'; fi
pass 'matching package receipts survive official Mason registry metadata changes'

for scenario in wrong-package wrong-source-package wrong-version; do
  if run_mason_case "$scenario" "$CASE_DIR/mason-$scenario.out" "$CASE_DIR/mason-$scenario.log"; then
    fail "Mason receipt accepted $scenario identity"
  fi
  assert_contains "$CASE_DIR/mason-$scenario.out" 'angular-language-server'
done
pass 'Mason receipts reject wrong receipt names, source packages, and source versions'

if run_mason_case angular-executable-missing "$CASE_DIR/mason-angular-executable.out" "$CASE_DIR/mason-angular-executable.log"; then
  fail 'successful handle was accepted without its package executable'
fi
assert_contains "$CASE_DIR/mason-angular-executable.out" 'angular-language-server'
if grep -Fq 'install biome' "$CASE_DIR/mason-angular-executable.log"; then fail 'Mason continued after angular-language-server executable verification failed'; fi
pass 'post-install executable verification stops later Mason packages'

if run_mason_case markdown-failure "$CASE_DIR/mason-failure.out" "$CASE_DIR/mason-failure.log"; then
  fail 'closed-failure Mason handle was accepted'
fi
assert_contains "$CASE_DIR/mason-failure.out" 'markdown-toc'
assert_contains "$CASE_DIR/mason-failure.out" 'wget exited with status 8'
if grep -Fq 'install markdownlint-cli2' "$CASE_DIR/mason-failure.log"; then fail 'Mason continued after required markdown-toc failed'; fi
pass 'required markdown-toc failure is package-specific and stops later packages'

if run_mason_case secret-failure "$CASE_DIR/mason-secret.out" "$CASE_DIR/mason-secret.log"; then
  fail 'Mason callback failure containing a secret was accepted'
fi
assert_contains "$CASE_DIR/mason-secret.out" 'download failed?token=<redacted>'
if grep -Fq 'do-not-print' "$CASE_DIR/mason-secret.out"; then fail 'Mason callback detail exposed a secret'; fi
pass 'Mason callback failure detail is bounded to safe redacted text'

if run_mason_case markdown-aborted "$CASE_DIR/mason-aborted.out" "$CASE_DIR/mason-aborted.log"; then
  fail 'aborted Mason handle was accepted'
fi
assert_contains "$CASE_DIR/mason-aborted.out" 'markdown-toc'
assert_contains "$CASE_DIR/mason-aborted.out" 'installation aborted'
if grep -Fq 'install markdownlint-cli2' "$CASE_DIR/mason-aborted.log"; then fail 'Mason continued after required markdown-toc was aborted'; fi
pass 'aborted markdown-toc install is package-specific and stops later packages'

if ! run_mason_case biome-warning "$CASE_DIR/mason-biome.out" "$CASE_DIR/mason-biome.log"; then
  fail 'successful Biome install was rejected for a benign schema warning'
fi
[[ "$(grep -c '^install ' "$CASE_DIR/mason-biome.log")" -eq 11 ]] || fail 'Biome warning prevented later pinned packages'
pass 'Biome schema warning is nonfatal only after successful package completion and verification'

for scenario in biome-receipt-missing biome-executable-missing; do
  if run_mason_case "$scenario" "$CASE_DIR/$scenario.out" "$CASE_DIR/$scenario.log"; then
    fail "Biome warning was accepted without verified state: $scenario"
  fi
  assert_contains "$CASE_DIR/$scenario.out" 'biome'
done
pass 'Biome warning remains fatal when its receipt or executable verification fails'

if run_mason_case timeout "$CASE_DIR/mason-timeout.out" "$CASE_DIR/mason-timeout.log"; then
  fail 'unfinished Mason handle escaped the bounded timeout'
fi
assert_contains "$CASE_DIR/mason-timeout.out" 'markdown-toc'
assert_contains "$CASE_DIR/mason-timeout.out" 'timed out'
assert_contains "$CASE_DIR/mason-timeout.log" 'wait 600000'
pass 'unfinished Mason handle fails with a bounded package-specific timeout'

if run_mason_case callback-absent "$CASE_DIR/mason-callback-absent.out" "$CASE_DIR/mason-callback-absent.log"; then
  fail 'closed Mason handle was accepted without its result callback'
fi
assert_contains "$CASE_DIR/mason-callback-absent.out" 'markdown-toc'
assert_contains "$CASE_DIR/mason-callback-absent.out" 'closed without a result callback'
pass 'closed handle without a Mason result callback fails package-specifically'

if run_mason_case closed-mismatch "$CASE_DIR/mason-closed-mismatch.out" "$CASE_DIR/mason-closed-mismatch.log"; then
  fail 'successful Mason callback was accepted before its handle closed'
fi
assert_contains "$CASE_DIR/mason-closed-mismatch.out" 'markdown-toc'
assert_contains "$CASE_DIR/mason-closed-mismatch.out" 'callback completed but handle did not close'
pass 'successful callback still requires the Mason handle to close'

: >"$COMMAND_LOG"
export DOTFILES_WORKSTATION_TEST_OS_VERSION=24.04
if "$ROOT/ubuntu/lib/runtime-bootstrap.sh" --approve-runtime-bootstrap >"$CASE_DIR/platform.out" 2>&1; then
  fail 'runtime bootstrap accepted an unsupported platform'
fi
[[ ! -s "$COMMAND_LOG" ]] || fail 'unsupported platform reached a runtime command'
export DOTFILES_WORKSTATION_TEST_OS_VERSION=26.04
pass 'unsupported platform is rejected before runtime mutation'

export RUNTIME_TEST_TIMEOUT_SECONDS=1
export RUNTIME_TEST_NVIM_SLEEP=3
if "$ROOT/ubuntu/lib/runtime-bootstrap.sh" --approve-runtime-bootstrap >"$CASE_DIR/timeout.out" 2>&1; then
  fail 'hung Neovim bootstrap escaped the bounded timeout'
fi
assert_contains "$CASE_DIR/timeout.out" 'bounded 1s timeout'
unset RUNTIME_TEST_TIMEOUT_SECONDS RUNTIME_TEST_NVIM_SLEEP
pass 'hung Neovim bootstrap fails at the bounded outer timeout'

export RUNTIME_TEST_NVIM_STATUS=7
export RUNTIME_TEST_NVIM_OUTPUT=$'RUNTIME_BOOTSTRAP_FAILED\nruntime-bootstrap.lua:99: Mason package install failed for markdown-toc: wget exited with status 8\nstack traceback:'
if "$ROOT/ubuntu/lib/runtime-bootstrap.sh" --approve-runtime-bootstrap >"$CASE_DIR/failure.out" 2>&1; then
  fail 'failed Neovim bootstrap returned success'
fi
if grep -Fq 'check-runtime --repair' "$COMMAND_LOG"; then fail 'ordinary failure selected ICU repair'; fi
assert_contains "$CASE_DIR/failure.out" 'Mason package install failed for markdown-toc'
pass 'failed bootstrap surfaces package-specific detail without broad ICU repair'

export RUNTIME_TEST_NVIM_OUTPUT='RUNTIME_BOOTSTRAP_MARKSMAN_ICU'
if "$ROOT/ubuntu/lib/runtime-bootstrap.sh" --approve-runtime-bootstrap >"$CASE_DIR/icu.out" 2>&1; then
  fail 'ICU retry fixture unexpectedly succeeded'
fi
assert_contains "$COMMAND_LOG" 'check-runtime --repair marksman-icu --approve-packages'
pass 'ICU repair is selected only for the exact missing-ICU marker'

for pin in angular-language-server$'\t'22.1.5 biome$'\t'2.5.12 marksman$'\t'2026-02-08 stylua$'\t'v2.5.2 tree-sitter$'\t'0.27.0; do
  assert_contains "$ROOT/ubuntu/runtime.lock.tsv" "$pin"
done
pass 'runtime lock records representative exact package and CLI pins'
