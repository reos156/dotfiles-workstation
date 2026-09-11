# Neovim source inventory

This inventory accounts for the **49 active source files observed for this snapshot** under `~/.config/nvim`. User-authored configuration is copied faithfully; only portable path/name substitutions are adapted. Generated dictionaries and obsolete template metadata are excluded.

| # | Active source path | Published treatment |
|---:|---|---|
| 1 | `.markdownlint-cli2.yaml` | Copied. |
| 2 | `.neoconf.json` | Copied. |
| 3 | `LICENSE` | Excluded: obsolete upstream/template metadata, not runtime configuration. |
| 4 | `init.lua` | Portable-variable adaptation: preserves default Linuxbrew discovery through the well-known `/home/linuxbrew/.linuxbrew/bin` prefix, then dynamically discovers other executable `brew` prefixes. |
| 5 | `lazy-lock.json` | Explicit lock-metadata adaptation: all 69 source pins are preserved and the previously published explicit MiniDiff pin is added, for 70 entries total. |
| 6 | `lazyvim.json` | Copied. |
| 7 | `lua/config/autocmds.lua` | Copied. |
| 8 | `lua/config/gentleman/utils.lua` | Copied. |
| 9 | `lua/config/keymaps.lua` | Copied, including deferred defects and Obsidian mappings. |
| 10 | `lua/config/lazy.lua` | Copied, including enabled/disabled extras. |
| 11 | `lua/config/nodejs.lua` | Copied; paths already use home expansion/system discovery. |
| 12 | `lua/config/options.lua` | Copied. |
| 13 | `lua/plugins/avante.lua` | Copied; user-authored prompt preserved byte-for-byte. Disabled by `disabled.lua`. |
| 14 | `lua/plugins/claude-code.lua` | Copied; disabled by `disabled.lua`. |
| 15 | `lua/plugins/code-companion.lua` | Copied; user-authored prompts preserved. Disabled by `disabled.lua`. |
| 16 | `lua/plugins/codecompanion/codecompanion-notifier.lua` | Copied; dormant while CodeCompanion is disabled. |
| 17 | `lua/plugins/colorscheme.lua` | Copied, including known nested-spec defect. |
| 18 | `lua/plugins/copilot-chat.lua` | Copied; prompts preserved. Disabled by `disabled.lua`. |
| 19 | `lua/plugins/copilot.lua` | Copied; disabled by `disabled.lua`. |
| 20 | `lua/plugins/disabled.lua` | Copied; authoritative negative specs preserve activation state. |
| 21 | `lua/plugins/editor.lua` | Copied. |
| 22 | `lua/plugins/fzflua.lua` | Copied. |
| 23 | `lua/plugins/gemini.lua` | Copied; disabled by `disabled.lua`. |
| 24 | `lua/plugins/markdown-lint.lua` | Copied. |
| 25 | `lua/plugins/markdown-preview.lua` | Copied. |
| 26 | `lua/plugins/markdown.lua` | Copied. |
| 27 | `lua/plugins/minidiff.lua` | Copied; lockfile pin retained. |
| 28 | `lua/plugins/multi-line.lua` | Copied. |
| 29 | `lua/plugins/nvim-dap.lua` | Copied, including deferred `get_args` and dotenv defects. |
| 30 | `lua/plugins/obsidian.lua` | Portable-variable adaptation for path/workspace; remains disabled. |
| 31 | `lua/plugins/oil.lua` | Copied, including deferred silent auto-write behavior. |
| 32 | `lua/plugins/opencode.lua` | Copied; disabled by `disabled.lua`. |
| 33 | `lua/plugins/overrides.lua` | Copied. |
| 34 | `lua/plugins/precognition.lua` | Copied; disabled by `disabled.lua`. |
| 35 | `lua/plugins/rip.lua` | Copied. |
| 36 | `lua/plugins/screenkey.lua` | Copied. |
| 37 | `lua/plugins/smear.lua` | Copied; disabled by `disabled.lua`. |
| 38 | `lua/plugins/treesitter.lua` | Copied with explicit source commit. |
| 39 | `lua/plugins/twilight.lua` | Copied. |
| 40 | `lua/plugins/ui.lua` | Representation-only adaptation: the dashboard header's 13 padded rows are quoted and newline-joined to remove source trailing whitespace while preserving the evaluated 1,846-byte header and all deferred runtime overlaps. |
| 41 | `lua/plugins/veil.lua` | Copied. |
| 42 | `lua/plugins/vim-be-good.lua` | Copied. |
| 43 | `lua/plugins/vim-tmux-navigation.lua` | Copied. |
| 44 | `lua/plugins/which-key.lua` | Copied, including duplicate configuration. |
| 45 | `spell/en.utf-8.spl` | Excluded: generated binary dictionary. |
| 46 | `spell/en_custom.txt` | Excluded: 955,453-line merged system-dictionary dump; provenance cannot isolate custom terms. |
| 47 | `spell/en_words.txt` | Excluded: 174,807-line system English dictionary dump. |
| 48 | `spell/es_words.txt` | Excluded: 782,970-line system Spanish dictionary dump with a source-machine path header. |
| 49 | `stylua.toml` | Copied. |

## Local Obsidian override contract

Obsidian remains disabled. Before enabling it, set:

```bash
export DOTFILES_NVIM_OBSIDIAN_PATH="$HOME/Documents/notes"
export DOTFILES_NVIM_OBSIDIAN_WORKSPACE="notes"
```

`DOTFILES_NVIM_OBSIDIAN_PATH` must be an existing directory. The workspace variable is optional and defaults to `notes`. Do not commit a personal path.

An installing AI agent must:

1. Search only user-approved roots for candidate note directories (for example `$HOME/Documents` and mounted document roots).
2. If exactly one credible directory exists, present it for confirmation; if zero or multiple exist, ask the human to choose rather than guessing.
3. Write the exports to a human-approved, Git-ignored local shell file or local environment manager, never to this repository.
4. Start an isolated shell and validate `[[ -d "$DOTFILES_NVIM_OBSIDIAN_PATH" ]]` plus `nvim --headless -u NONE -i NONE -c 'lua assert(vim.env.DOTFILES_NVIM_OBSIDIAN_PATH)' -c qa`.
5. Leave Obsidian `enabled = false` if the directory is unresolved. Enabling the plugin is a separate reviewed change.

## Spell dictionary result

No custom words were guessed. [`spell/custom-words.txt`](../ubuntu/config/nvim/spell/custom-words.txt) is an empty, auditable future source list; [`spell/README.md`](../ubuntu/config/nvim/spell/README.md) documents isolated regeneration. Generated `.spl` output stays ignored.

## Non-source artifacts

Late-generated `lua/plugins/.atl/` registry/cache files and `lua/plugins/.gitignore` were not part of the 49-file active snapshot and are excluded as tool metadata rather than Neovim configuration. The three pre-existing curated-bundle modules (`lua/config/runtime.lua`, `lua/plugins/fzf.lua`, and `lua/plugins/git.lua`) remain inert compatibility stubs so they cannot add behavior beyond this snapshot.
