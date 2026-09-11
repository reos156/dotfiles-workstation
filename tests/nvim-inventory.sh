#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"
NVIM="$ROOT/ubuntu/config/nvim"
INVENTORY="$ROOT/docs/nvim-configuration-inventory.md"

fail() { printf 'Inventory check failed: %s\n' "$1" >&2; exit 1; }

expected=(
  .markdownlint-cli2.yaml .neoconf.json init.lua lazy-lock.json lazyvim.json stylua.toml
  lua/config/autocmds.lua lua/config/gentleman/utils.lua lua/config/keymaps.lua
  lua/config/lazy.lua lua/config/nodejs.lua lua/config/options.lua
  lua/plugins/avante.lua lua/plugins/claude-code.lua lua/plugins/code-companion.lua
  lua/plugins/codecompanion/codecompanion-notifier.lua lua/plugins/colorscheme.lua
  lua/plugins/copilot-chat.lua lua/plugins/copilot.lua lua/plugins/disabled.lua
  lua/plugins/editor.lua lua/plugins/fzflua.lua lua/plugins/gemini.lua
  lua/plugins/markdown-lint.lua lua/plugins/markdown-preview.lua lua/plugins/markdown.lua
  lua/plugins/minidiff.lua lua/plugins/multi-line.lua lua/plugins/nvim-dap.lua
  lua/plugins/obsidian.lua lua/plugins/oil.lua lua/plugins/opencode.lua
  lua/plugins/overrides.lua lua/plugins/precognition.lua lua/plugins/rip.lua
  lua/plugins/screenkey.lua lua/plugins/smear.lua lua/plugins/treesitter.lua
  lua/plugins/twilight.lua lua/plugins/ui.lua lua/plugins/veil.lua
  lua/plugins/vim-be-good.lua lua/plugins/vim-tmux-navigation.lua lua/plugins/which-key.lua
)

[[ "${#expected[@]}" -eq 44 ]] || fail 'copied/adapted file fixture must contain 44 paths'
[[ "$(grep -Ec '^\| [0-9]+ \|' "$INVENTORY")" -eq 49 ]] || fail 'inventory must contain exactly 49 numbered source rows'
for rel in "${expected[@]}"; do
  [[ -f "$NVIM/$rel" ]] || fail "published file missing: $rel"
  grep -Fq "\`$rel\`" "$INVENTORY" || fail "inventory row missing: $rel"
done
for excluded in LICENSE spell/en.utf-8.spl spell/en_custom.txt spell/en_words.txt spell/es_words.txt; do
  [[ ! -e "$NVIM/$excluded" ]] || fail "excluded source payload was published: $excluded"
  grep -Fq "\`$excluded\`" "$INVENTORY" || fail "excluded source is not accounted for: $excluded"
done

DISABLED="$NVIM/lua/plugins/disabled.lua"
for plugin in \
  jonroosevelt/gemini-cli.nvim zbirenbaum/copilot.lua giuxtaposition/blink-cmp-copilot \
  akinsho/bufferline.nvim yetone/avante.nvim CopilotC-Nvim/CopilotChat.nvim \
  NickvanDyke/opencode.nvim olimorris/codecompanion.nvim tris203/precognition.nvim \
  sphamba/smear-cursor.nvim coder/claudecode.nvim; do
  grep -Fq "$plugin" "$DISABLED" || fail "negative spec missing: $plugin"
done
[[ "$(grep -c 'enabled = false' "$DISABLED")" -eq 11 ]] || fail 'disabled.lua activation-state count changed'
grep -Fq 'enabled = false' "$NVIM/lua/plugins/obsidian.lua" || fail 'Obsidian must remain disabled'
grep -Fq -- '-- { import = "lazyvim.plugins.extras.editor.snacks_explorer" }' "$NVIM/lua/config/lazy.lua" || fail 'Snacks Explorer import activation changed'
grep -Fq '{ import = "lazyvim.plugins.extras.editor.mini-files" }' "$NVIM/lua/config/lazy.lua" || fail 'Mini Files import is missing'
grep -Fq '{ import = "lazyvim.plugins.extras.lang.markdown" }' "$NVIM/lua/config/lazy.lua" || fail 'Markdown extra is missing'
grep -Fq 'Este GPT es un clon del usuario' "$NVIM/lua/plugins/code-companion.lua" || fail 'original Spanish AI prompt is missing'
grep -Fq '"mini.diff"' "$NVIM/lazy-lock.json" || fail 'explicit MiniDiff pin is missing'
[[ "$(grep -Ec '^  \"' "$NVIM/lazy-lock.json")" -eq 70 ]] || fail 'adapted lockfile must contain 69 source pins plus MiniDiff'
grep -Fq 'Explicit lock-metadata adaptation: all 69 source pins are preserved' "$INVENTORY" || fail 'inventory must classify lazy-lock.json as adapted'
grep -Fq 'lock_metadata_adaptation: preserve-all-69-source-pins-and-add-published-explicit-minidiff-pin' "$ROOT/manifest.yaml" || fail 'manifest lockfile adaptation is missing'
grep -Fq 'Representation-only adaptation: the dashboard header' "$INVENTORY" || fail 'inventory must classify ui.lua as a representation-only adaptation'
grep -Fq 'header = table.concat({' "$NVIM/lua/plugins/ui.lua" || fail 'dashboard header must use a trailing-whitespace-safe representation'
grep -Fq 'dashboard_header: quoted-padded-rows-joined-with-original-newline-semantics' "$ROOT/manifest.yaml" || fail 'manifest dashboard representation adaptation is missing'

printf 'ok - 49-file inventory parity and activation state are explicit\n'
