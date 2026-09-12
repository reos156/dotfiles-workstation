# Diagnose optional runtime problems safely

Run `./ubuntu/check-runtime.sh` after installation when Neovim, Marksman, or Herdr audio integration behaves unexpectedly. With no arguments it is read-only and returns nonzero only for detected failures; absent optional tools are reported as `OPTIONAL`.

These checks and repairs are not part of `base-config`, are never run automatically, and do not make every custom runtime layout repairable.

## Quick path

```bash
./ubuntu/check-runtime.sh
```

Review the result before choosing exactly one repair:

```bash
./ubuntu/check-runtime.sh --repair vim-parser \
  --approve-runtime-repair --approve-downloads
./ubuntu/check-runtime.sh --repair marksman-icu --approve-packages
./ubuntu/check-runtime.sh --repair paplay --approve-packages
```

Approval flags record a decision; they do not provide a password. Run an approved package command in an interactive Ubuntu terminal when `sudo` needs authentication. Never send a password through an agent or redirected input.

## What each check does

| Capability | Diagnostic | Approved repair |
|---|---|---|
| Vim Treesitter highlights | Starts Neovim with temporary `HOME` and XDG config/state/cache roots, the existing real XDG data root, `--headless -u NONE -i NONE --noplugin`, and only the existing Neovim site plus `lazy/nvim-treesitter` runtime paths. Neovim or the plugin being absent is optional; with the plugin installed, an absent parser, absent query file, nil query, or compilation error is a failure. | Uses only the installed nvim-treesitter Lua module and `install({'vim'}, {force=true, summary=true}):pwait(600000)`. A missing parser may therefore be restored. If the plugin query remains physically absent or nil after reinstalling the parser, the command fails with manual plugin/runtime remediation instead of reporting success. It never loads the live init, bootstraps Lazy, or runs a broad update. |
| Marksman | Finds `marksman` through `PATH`, then the existing Mason bin directory. Runs `--version` with core dumps disabled and stderr suppressed. The exact missing-ICU diagnostic is distinguished from all other failures. | On Ubuntu only, selects a single package matching `^libicu[0-9]+$` with an available candidate in current apt metadata. Zero or multiple candidates require manual package review. |
| `paplay` | Checks command availability only when Herdr is installed. It never plays audio or starts/restarts a service. | Installs `pulseaudio-utils` on Ubuntu. It does not run Herdr or audio playback. |

Repairs check the selected capability first. Healthy capabilities and absent optional parent tools are no-ops. An installed nvim-treesitter runtime with a missing parser or query is not an absent parent. A repair is successful only when its targeted filesystem and runtime-query recheck passes.

## Shell glyph and prompt rendering

The managed `.zshrc` evaluates locale precedence (`LC_ALL`, then `LC_CTYPE`, then `LANG`) before loading plugins. If the effective locale is absent, `C`, or `POSIX`, it selects an installed `C.UTF-8` or `C.utf8` for `LC_CTYPE`. An ASCII `LC_ALL` is unset because it would otherwise override that selection. A valid existing UTF-8 locale is not changed, and no system-wide locale is configured.

If startup reports that no portable UTF-8 locale is available, install or generate `C.UTF-8`/`C.utf8` through the operating system's supported locale workflow, then start a new shell. The warning is nonfatal: without that locale, Ruby tools such as `colorls` may encode through US-ASCII and omit Nerd Font glyphs.

Prompt layout and rendering are separate boundaries:

- Zsh/Starship provide the published Catppuccin Mocha Powerline layout.
- The terminal must provide truecolor, the configured Nerd Font glyph coverage, and a shell-driven prompt surface.
- Font, theme, and terminal input settings remain manual; diagnostics and repairs do not change them.

A report of duplicated autosuggestion text disappeared after the Starship/locale update, but causality is unknown. The managed plugin order and plugin set are intentionally unchanged; this work does not claim a proven autosuggestion fix.

## Source-toolchain versus runtime repair

`ubuntu/install.sh --profile source-toolchain` is the complete installer boundary. It requires package, download, and runtime-bootstrap approval before mutation. After installing and snapshotting managed configuration, it restores enabled plugin checkouts from the repository `lazy-lock.json`, installs the recorded Mason package versions from the official registry plus the tree-sitter CLI/parser pins in `ubuntu/runtime.lock.tsv`, and runs the core runtime verifier with `~/.local/bin` and Mason's bin directory on `PATH`.

The configuration snapshot remains config-only. Tool versions stay under the XDG data root, and `tools/activation.tsv` records the prior owned link or absence before activation in `~/.local/bin`. To roll back manually, inspect that ledger and point a link to a retained version. Do not copy a tool directory into a configuration snapshot or delete a retained version while an active link targets it.

Homebrew is installed in the user-local version root rather than the standard Linuxbrew prefix; its wrapper disables automatic updates, and bottles that require the standard prefix may be unavailable. The verified colorls gem may fetch transitive dependencies from the official RubyGems registry after download approval; those dependency versions are not fully locked. `pulseaudio-utils` establishes command availability only, not working playback.

Runtime data under the XDG data root remains outside managed configuration snapshots. Existing conflicting Lazy or tree-sitter bootstrap state fails closed; the installer does not overwrite a customized lock blindly. The official Mason registry evolves independently; receipts must still match the expected package name and source version. Mason npm and Colorls RubyGem transitive dependency graphs are not wholly frozen. Herdr audio behavior or startup, `win32yank.exe`, Zellij, Carapace, Docker/environment setup, and the unknown autosuggestion root cause are not installation-success claims.

A manually assembled Docker environment passed functional checks. Later automated clean-install attempts found defects in raw Herdr filename handling, safe internal Node symlink handling, and Colorls `.gem` staging plus `GEM_HOME`; those paths are now covered by local regression tests. No fresh full automated end-to-end install has passed after all of the latest corrections, so the focused and offline suite results must not be presented as that proof.

## Safety and rollback boundary

- Parser runtime changes and downloads are outside managed snapshots; parser rollback is manual.
- Apt package rollback is not automated. Package commands use `apt-get install --no-install-recommends --no-upgrade` and never guess an ICU version.
- No repair edits Neovim configuration, plugin lockfiles, shell configuration, or Herdr state.
- Diagnostics do not read shell histories, load live Neovim initialization/plugins, print raw tool stderr, run audio, restart services, or install anything.
- Existing plugin/parser/Mason layouts outside standard Neovim data paths are reported as optional or require a manual supported workflow.
- This is targeted reconciliation, not a full toolchain installer and not a guarantee against every runtime incompatibility.

## Evidence provenance

The source-machine inventory remains [`source-baseline-2026-09-11.md`](source-baseline-2026-09-11.md). It records observed source versions; it is not evidence that a repair is universally correct.

The runtime remedies above are reconciled-machine evidence from full installation sessions under `docs/pi-sessions-full-20260912T054344Z`:

| Session evidence | Observed outcome | Generalized boundary |
|---|---|---|
| Editor session `01a092bf`, lines 22–46 | Vim highlights failed with `Invalid node type tab`; reinstalling only the Vim parser with an asynchronous wait repaired it. | Target only the Vim parser. Do not infer permission for `:Lazy update`. |
| Editor session `01a092bf`, lines 55–75 | Marksman aborted because no valid ICU package was installed; `libicu78` repaired that Ubuntu 26.04.1 machine. | Discover exactly one current apt candidate. Never hardcode `libicu78` globally or apply an invariant-globalization workaround. |
| Integration session `01a091f9`, lines 95–122 | `paplay` was absent; installing `pulseaudio-utils` restored user-confirmed sound. | Check availability only and repair only when Herdr is relevant; never play audio during diagnostics. |

There is no full-session evidence that the installer caused a WSL shutdown. No shutdown/restart behavior is included. Herdr state and agent/subagent lifecycle bridges remain excluded.
