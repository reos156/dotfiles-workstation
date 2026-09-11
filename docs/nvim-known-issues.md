# Neovim known-issues backlog

The full-personalization snapshot intentionally preserves current behavior. The defects and overlaps below are documented, **not fixed in this iteration**; each belongs in a later, focused commit with behavior tests.

| File / symbol | Current effect | Future task |
|---|---|---|
| `lua/plugins/nvim-dap.lua` / `get_args` | `<leader>da` references an undefined global and cannot reliably run with arguments. | Define and test a local argument collector. |
| `lua/plugins/nvim-dap.lua` / `load_env_variables` | The `%w`-only parser drops quoted values, spaces, punctuation, exports, and empty values. | Replace it with a specified dotenv parser and fixtures. |
| `lua/plugins/oil.lua` / `BufLeave` | Modified Oil buffers use `silent! write`, hiding write failures while applying filesystem edits. | Surface errors and add an Oil integration test. |
| `lua/plugins/ui.lua` / Lualine spec | Uses legacy `requires` instead of Lazy's `dependencies`, so icon dependency ordering is uncertain. | Migrate the field after testing startup order. |
| `lua/plugins/ui.lua` and `lua/plugins/which-key.lua` | WhichKey is configured twice with merge/order-dependent behavior. | Consolidate the two specs without losing key groups. |
| `lua/plugins/copilot.lua`, `gemini.lua`, `precognition.lua`, `smear.lua`, and `disabled.lua` | Positive specs coexist with later negative specs; their code is dead while disabled and activation depends on Lazy merge order. | Add one explicit feature-gate source of truth. |
| `lua/plugins/editor.lua` plus LazyVim Git defaults | `git.nvim`, Gitsigns, and MiniDiff overlap in Git presentation/actions. | Assign explicit ownership per Git behavior. |
| `lua/config/lazy.lua`, `lua/plugins/fzflua.lua`, `lua/plugins/oil.lua`, and Mini Files extra | Snacks/Fzf pickers and Oil/Mini Files explorers overlap. | Choose primary/fallback tools and remove duplicate mappings in a separate migration. |
| `lua/config/gentleman/utils.lua` / `hexToHSL` | Requires `solarized-osaka.hsluv` but does not use the returned module; the dependency is dormant/unprovided. | Remove or use the dependency after a conversion test captures intent. |
| `lua/config/keymaps.lua` / Obsidian mappings | Global Obsidian commands are registered although Obsidian is disabled. | Gate mappings with the same future feature flag as the plugin. |
| `lua/config/keymaps.lua` / `SaveFile` | `pcall` around `silent! write` can report “Saved!” after a suppressed write failure. | Stop suppressing the error and test readonly/write-failure buffers. |
| `lua/config/keymaps.lua` / `<C-c>` | A broad insert/normal/visual mapping forces terminal-normal escape semantics and overrides normal interrupt behavior. | Scope the mapping by mode after documenting intended UX. |
| `lua/plugins/ui.lua` / CodeCompanion Lualine extension | Statusline callbacks directly require CodeCompanion even though that plugin is disabled. | Guard the require or register the extension only when enabled. |
| `lua/plugins/colorscheme.lua` / outer plugin table | The nested table shape is likely malformed and may prevent colorscheme specs from being interpreted as intended. | Flatten specs and verify Lazy's resolved graph. |

Other intentional behavior to review later includes automatic Lazy update checking, executable discovery/version ordering in `nodejs.lua`, and user-authored AI tool prompts that permit approved command/file operations. None is silently changed here.
