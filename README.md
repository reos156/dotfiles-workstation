# dotfiles-workstation

Replicate a portable Windows + Ubuntu WSL workstation with the full user-authored Neovim/LazyVim personalization. Plugin sources remain upstream, current enabled/disabled state is preserved, runtime tools and personal paths are resolved locally, and generated editor state stays outside the bundle.

## Quick path

1. Clone the canonical repository, then enter it:

   ```bash
   git clone https://github.com/reos156/dotfiles-workstation.git
   cd dotfiles-workstation
   ```

2. Complete [`windows/PREREQUISITES.md`](windows/PREREQUISITES.md) and [`windows/WARP-SETUP.md`](windows/WARP-SETUP.md) manually. Windows changes are never automated.
3. Choose the fidelity target before installing anything optional:

   | Fidelity choice | Availability and contract |
   |---|---|
   | `base-config` | **Implemented.** Installs only the repository's APT, recorded Zsh download, and managed-configuration baseline. |
   | `compatible-toolchain` | **Not implemented.** A future, separately reviewed installation must define compatibility constraints and package-source policy. |
   | `source-baseline` | **Versioned observed reference.** [`docs/source-baseline-2026-09-11.md`](docs/source-baseline-2026-09-11.md) records the active versions observed on the source workstation. Exact installation remains separately reviewed because source URLs, checksums/signatures, activation, and rollback are not fully captured. |

   These names describe a pre-install human decision, not `install.sh` options. The installer has no `compatible-toolchain` or `source-baseline` flag or state. The observed baseline is a reconciliation target, not an automatic installer profile. The installer's only implemented profile is **`base-config`**:

   | Scope | `base-config` behavior |
   |---|---|
   | APT baseline | Installs `zsh`, `git`, `curl`, certificates, `fzf`, `bat`, and `fd-find` after approval. |
   | Recorded Zsh downloads | Clones the recorded Oh My Zsh and plugin revisions after approval. |
   | Managed configuration | Installs the five documented destinations and snapshots changed prior state. |
   | Optional commands | Configures integrations only when commands are already present; binary installation is deferred. |
   | Neovim runtime/plugins | Remains a separate optional bootstrap and health scope. |

4. In Ubuntu on WSL, inspect [`manifest.yaml`](manifest.yaml), then preview the complete configuration change:

   ```bash
   ./ubuntu/install.sh --dry-run --approve-packages --approve-downloads
   ```

5. After explicit approval for `sudo` and upstream downloads, install:

   ```bash
   ./ubuntu/install.sh --approve-packages --approve-downloads
   ```

   On a prepared or offline system, use `--skip-packages --skip-downloads`. These flags skip shell dependencies; Lazy.nvim performs its own plugin bootstrap only when Neovim is later started with network access.

   If an assistant or CI-like runner has no interactive TTY, `sudo` may require direct human authentication. Run the approved command yourself in an interactive Ubuntu terminal. Never send a system password through an agent, chat, command argument, form, or redirected standard input.

6. Start the configured shell with `exec zsh -l`, or open a new Warp Ubuntu tab. Then verify:

   ```zsh
   printf '%s\n' "$SHELL"
   command -v zsh
   alias ls
   ```

   `chsh` affects future login sessions; it cannot replace the shell process already running.

7. Run the no-network checks:

   ```bash
   ./tests/run.sh
   ./ubuntu/verify.sh
   ```

Validation has three distinct meanings:

| Result | Meaning | Next action |
|---|---|---|
| `install` succeeds | The managed write and snapshot flow completed. | Start a new shell or tab. |
| `verify` passes | Managed source and deployed configuration are identical. | Treat this as the pre-personalization safe point. |
| `verify` reports `CHANGED` | A managed destination drifted after installation. | Diff it and preserve or restore deliberately; this is not automatically an install failure. |

`verify.sh` compares every managed file and the complete Neovim configuration tree. It parses Lua with `luac` or Neovim when available, but does not load plugins, contact the network, or validate plugin, parser, Mason, data, state, or cache health.

Optional post-install runtime diagnostics are separate and read-only by default:

```bash
./ubuntu/check-runtime.sh
```

See [`docs/installation-runtime-remedies.md`](docs/installation-runtime-remedies.md) before explicitly approving any targeted repair. Runtime repairs are outside managed snapshots and are not a full toolchain installer.

### Starship visual baseline

[`ubuntu/config/starship.toml`](ubuntu/config/starship.toml) is this project's functional prompt baseline. It uses the Catppuccin Mocha palette and a minimal two-line layout: the first line shows the directory and time, plus Git branch/status, detected language-tool versions, and command duration when those modules have applicable context; the second line is the colored prompt character. Warp with **Shell (PS1)** input, **Hack Nerd Font Mono**, and the documented Catppuccin theme should display that structure.

External Powerline-style segment layouts are separate personalization. They are not bundled and are not an installation-success criterion.

## Human checkpoints

| Checkpoint | Human decision |
|---|---|
| Windows prerequisites | Install WSL 2, Ubuntu, Warp, and Hack Nerd Font Mono manually. |
| Package changes | Approve `sudo apt-get update` and manifest-listed apt packages. |
| Shell dependency downloads | Approve cloning the recorded Oh My Zsh upstreams. |
| Neovim bootstrap | Choose when Neovim may download lockfile-recorded plugins. |
| Login shell | Approve `--set-default-shell`; otherwise `chsh` is never called. |
| Existing configuration | Review the dry-run destination and snapshot boundary. |

An AI agent must not infer any approval from the repository's existence.

## Full Neovim personalization

The managed `${XDG_CONFIG_HOME:-$HOME/.config}/nvim` directory publishes the complete active personalization snapshot:

- LazyVim extras for Harpoon, Mini Files, Snacks picker, DAP, Biome, Prettier, ESLint, JSON, Markdown, Blink, MiniDiff, MiniSurround, and MiniHipatterns;
- Markdown rendering, browser preview, markdownlint-cli2 configuration, keymaps, and lock entries;
- custom Treesitter pinning, themes, dashboard/statusline UI, Tmux navigation, multi-cursor editing, Oil, Git helpers, DAP, and supporting utilities;
- AI/provider and Obsidian specifications plus the original user-authored prompts, without credentials or provider authentication;
- explicit negative specs that keep Copilot, CopilotChat, Avante, CodeCompanion, Claude Code, Gemini, OpenCode, Precognition, Smear, and related integrations disabled exactly as in the source snapshot.

Versioned or locked plugins are not necessarily enabled. Do not remove `enabled = false` merely because a spec or lock entry exists. Neovim itself must be installed separately at a LazyVim-supported version.

### Appearance defaults

The global Neovim colorscheme is **Catppuccin**. The Lualine/statusline theme is **Gentleman Kanagawa Blur**, and the dashboard header is intentionally user-authored. Configuration retained with `enabled = false` is inactive; its presence is not evidence that the related integration is running.

### Local overrides

Obsidian remains safely disabled and contains no personal path. Before a separately reviewed enablement, set `DOTFILES_NVIM_OBSIDIAN_PATH` to a confirmed existing notes directory and optionally set `DOTFILES_NVIM_OBSIDIAN_WORKSPACE`. See the deterministic human/agent workflow in [`docs/nvim-configuration-inventory.md`](docs/nvim-configuration-inventory.md).

Never commit personal paths, tokens, provider authentication, histories, or runtime databases. Before sharing or storing diagnostics, redact machine-specific paths, credentials, tokens, authentication material, shell histories, and credential-bearing command output. If candidate directories are ambiguous, an installing agent must ask the human and leave the integration disabled.

### Fidelity and known issues

This iteration copies behavior rather than repairing it. [`docs/nvim-configuration-inventory.md`](docs/nvim-configuration-inventory.md) accounts for all 49 active source files and dictionary exclusions. [`docs/nvim-known-issues.md`](docs/nvim-known-issues.md) records intentionally deferred defects and overlaps for later focused commits.

### First bootstrap (optional network check)

Normal startup bootstraps Lazy.nvim and lockfile-recorded plugins into Neovim's standard data directory. To test that download path without touching real user state, explicitly authorize the isolated check:

```bash
./tests/bootstrap.sh --approve-network
```

The script creates a temporary `HOME` and overrides all XDG config, data, state, and cache roots. It requires Git, Neovim, and network access, and removes its temporary tree afterward.

Configuration equality does not prove Neovim runtime health. After bootstrap or a Neovim/plugin change, run `:checkhealth nvim-treesitter`. Reconcile only the affected parser first (for example, reinstall that parser with the supported nvim-treesitter command), re-run targeted health, and inspect compatibility before any broad `:Lazy update`. Plugin checkouts, parsers, Mason packages, and other runtime state are outside the installer snapshot and rollback boundary.

### Controlled personalization updates

Treat [`ubuntu/config/nvim/lazy-lock.json`](ubuntu/config/nvim/lazy-lock.json) as explicitly adapted reviewed metadata: it preserves all 69 source pins and adds the required published MiniDiff pin, for 70 entries total.

1. Inventory the active source tree and compare it with [`docs/nvim-configuration-inventory.md`](docs/nvim-configuration-inventory.md).
2. Copy user-authored configuration without translating prompts or changing activation state.
3. Replace only machine-specific paths/names with documented portable variables; never copy secrets or runtime state.
4. Run `:Lazy update` only when deliberately updating plugins, then review every lockfile change, including disabled specs.
5. Run `./tests/run.sh` and `./ubuntu/verify.sh` against an isolated installed tree; use the optional network bootstrap only with approval.
6. Update the inventory and known-issues backlog with the same work unit.

Plugin checkouts are never copied or vendored, and `.git` directories are forbidden in this bundle.

## Distribution and normalized archive fallback

Git is the canonical distribution path. Use a normal clone or fetch so tracked bytes, executable bits, history, and review provenance remain available. An ordinary ZIP/TAR export is not the primary workflow.

When Git transport is unavailable, create a normalized fallback archive from the repository root with GNU tar and gzip:

```bash
git ls-files -z | tar -cf - --null --no-recursion --sort=name --mtime='@0' \
  --owner=0 --group=0 --numeric-owner --format=posix \
  --pax-option=delete=atime,delete=ctime --files-from=- | gzip -n > ../dotfiles-workstation.tar.gz
```

This command archives tracked paths only, sorts them, fixes numeric owner/group IDs and modification time, removes variable PAX access/change times, and suppresses the gzip timestamp. Those command-line options normalize archive metadata; repository file contents cannot control metadata added by an arbitrary archiver.

## Managed destinations

| Bundle source | Ubuntu destination | Snapshot kind |
|---|---|---|
| `ubuntu/config/zsh/.zshrc` | `$HOME/.zshrc` | file |
| `ubuntu/config/starship.toml` | `${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml` | file |
| `ubuntu/config/atuin/config.toml` | `${XDG_CONFIG_HOME:-$HOME/.config}/atuin/config.toml` | file |
| `ubuntu/config/herdr/config.toml` | `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml` | file |
| `ubuntu/config/nvim` | `${XDG_CONFIG_HOME:-$HOME/.config}/nvim` | directory |

Oh My Zsh and its plugins are cloned into `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-workstation/deps`. They are reproducible dependencies, not source-machine snapshot payloads.

The Herdr file is portable UI configuration only. This bundle does not install Herdr, Pi integrations, audio backends, or agent/subagent lifecycle bridges, and it does not promise indicators or completion sounds for those external components.

## Exact backup and rollback

A changed install creates one scoped snapshot:

```text
$HOME/.dotfiles-workstation/backups/<timestamp>/
```

Before the first managed-config write, the installer validates every bundled source and all five current destinations, including the complete Neovim tree. A rejected entry therefore leaves every managed destination unchanged and creates no snapshot.

`manifest.tsv` records each changed destination. Existing regular files are copied exactly; symlink targets are encoded and recreated without dereferencing. An existing Neovim directory is accepted only when its tree contains regular files, directories, and symlinks. That entire tree is copied into the self-contained snapshot before sibling-staged replacement. Sockets, devices, FIFOs, and other special entries are rejected before any snapshot or replacement.

Directory rollback validates the snapshot and current tree, stages restoration beside the destination, and preserves the displaced tree until the restored tree is in place. If Neovim config was absent before installation, rollback removes only the managed config directory.

```bash
./ubuntu/rollback.sh --list
./ubuntu/rollback.sh <timestamp>
```

Rollback is intentionally limited to the five managed destinations. It does not uninstall packages or remove downloaded shell dependencies.

## Excluded data and rollback boundary

The installer, verifier, and rollback never target:

- `${XDG_DATA_HOME:-$HOME/.local/share}/nvim` (plugin checkouts and Mason installations);
- `${XDG_STATE_HOME:-$HOME/.local/state}/nvim` (history, sessions, logs, and state);
- `${XDG_CACHE_HOME:-$HOME/.cache}/nvim` (compiled and downloaded caches).

The bundle includes AI/provider and Obsidian plugin configuration and original prompts, but excludes credentials, provider authentication, personal vault/project paths, histories, Warp account/session state, shell history, databases, sockets, logs, backups from other installers, generated dictionary bulk, and copied Git metadata.

The test suite runs installs and rollbacks only under an isolated temporary `HOME`, checks idempotence and exact file/symlink/directory restoration, rejects special directory entries, preserves all Neovim runtime roots, and cleans temporary artifacts by default. Set `DOTFILES_WORKSTATION_KEEP_TEST_ARTIFACTS=1` only for an explicit debugging run.

## Limitations

- Windows steps remain manual and depend on current Microsoft, Warp, and Nerd Fonts interfaces.
- The Oh My Zsh default branch is recorded but not commit-pinned; stable plugin releases are pinned where available.
- Neovim and optional command binaries require separately reviewed installation choices.
- Package and downloaded-dependency rollback are outside the snapshot contract.
