# dotfiles-workstation

Replicate a portable Windows + Ubuntu WSL workstation with a curated Neovim/LazyVim core. The installer manages reviewed configuration only: plugin sources remain upstream, runtime tools are discovered dynamically, and personal or generated editor state stays outside the bundle.

## Quick path

1. Clone the canonical repository, then enter it:

   ```bash
   git clone https://github.com/reos156/dotfiles-workstation.git
   cd dotfiles-workstation
   ```

2. Complete [`windows/PREREQUISITES.md`](windows/PREREQUISITES.md) and [`windows/WARP-SETUP.md`](windows/WARP-SETUP.md) manually. Windows changes are never automated.
3. In Ubuntu on WSL, inspect [`manifest.yaml`](manifest.yaml), then preview the complete configuration change:

   ```bash
   ./ubuntu/install.sh --dry-run --approve-packages --approve-downloads
   ```

4. After explicit approval for `sudo` and upstream downloads, install:

   ```bash
   ./ubuntu/install.sh --approve-packages --approve-downloads
   ```

   On a prepared or offline system, use `--skip-packages --skip-downloads`. These flags skip shell dependencies; Lazy.nvim performs its own plugin bootstrap only when Neovim is later started with network access.
5. Run the no-network checks:

   ```bash
   ./tests/run.sh
   ./ubuntu/verify.sh
   ```

`verify.sh` compares every managed file and the complete Neovim configuration tree. It parses Lua with `luac` or Neovim when available, but does not load plugins, contact the network, or write state.

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

## Neovim core

The managed `${XDG_CONFIG_HOME:-$HOME/.config}/nvim` directory provides:

- a portable Lazy.nvim bootstrap and LazyVim core;
- Catppuccin Mocha as the default transparent theme;
- FzfLua as the picker, including selection grep and project-root selection grep;
- portable Node discovery through active manager environments, `brew --prefix node`, then `PATH`;
- conditional WSL clipboard integration only when `win32yank.exe` is executable;
- MiniDiff signs and overlays using the official `git-split-diffs` Dark palette;
- Gitsigns hunk actions with its signs, line highlights, number highlights, and word diff disabled so MiniDiff exclusively owns diff rendering.

The selected core intentionally excludes overlapping file explorers, debuggers, Obsidian integration, and all AI integrations. LazyVim defaults still supply the coherent editing, LSP, formatting, completion, diagnostics, and Git foundation. Neovim itself must be installed separately at a LazyVim-supported version; this bundle does not choose a machine-specific package manager or binary path.

### First bootstrap (optional network check)

Normal startup bootstraps Lazy.nvim and lockfile-recorded plugins into Neovim's standard data directory. To test that download path without touching real user state, explicitly authorize the isolated check:

```bash
./tests/bootstrap.sh --approve-network
```

The script creates a temporary `HOME` and overrides all XDG config, data, state, and cache roots. It requires Git, Neovim, and network access, and removes its temporary tree afterward.

### Controlled plugin updates

Treat [`ubuntu/config/nvim/lazy-lock.json`](ubuntu/config/nvim/lazy-lock.json) as reviewed source metadata, not generated noise:

1. Install the bundle in an isolated or reviewable environment.
2. Run `:Lazy update` deliberately; never enable automatic updates.
3. Review plugin source and lockfile changes, especially LazyVim compatibility.
4. Copy back only the reviewed `lazy-lock.json` change.
5. Run `./tests/run.sh` and the optional isolated bootstrap check.
6. Commit configuration, tests, documentation, and lock metadata together as one work unit.

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

The bundle also excludes personal AI specs and prompts, provider settings, histories, credentials, vault and project paths, Warp account/session state, shell history, databases, sockets, logs, backups from other installers, and copied Git metadata.

The test suite runs installs and rollbacks only under an isolated temporary `HOME`, checks idempotence and exact file/symlink/directory restoration, rejects special directory entries, preserves all Neovim runtime roots, and cleans temporary artifacts by default. Set `DOTFILES_WORKSTATION_KEEP_TEST_ARTIFACTS=1` only for an explicit debugging run.

## Limitations

- Windows steps remain manual and depend on current Microsoft, Warp, and Nerd Fonts interfaces.
- The Oh My Zsh default branch is recorded but not commit-pinned; stable plugin releases are pinned where available.
- Neovim and optional command binaries require separately reviewed installation choices.
- Package and downloaded-dependency rollback are outside the snapshot contract.
