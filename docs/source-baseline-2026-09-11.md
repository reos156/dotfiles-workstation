# Source Workstation Observed Baseline — 2026-09-11

## Status and scope

This versioned observed reference was captured from the source workstation on 2026-09-11. It records the active command versions observed in that environment; those versions may differ from installed APT package versions.

The baseline remains observed evidence, while `./ubuntu/install.sh --profile source-toolchain` now provides the separately reviewed Ubuntu 26.04 Linux x86_64 reproduction path. The profile pins command assets in `ubuntu/toolchain.lock.tsv` and Neovim runtime inputs in `ubuntu/runtime.lock.tsv`; it does not turn the original observation into publisher proof.

No machine-specific executable paths are recorded here. A replay must verify both the resolved executable path and the command's reported version rather than infer the active tool from package-manager state alone.

## Reproduction evidence

| Evidence class | Tools | Meaning |
|---|---|---|
| Adjacent publisher checksum | Starship, Atuin | SHA256 came from the publisher's adjacent checksum asset. |
| Publisher checksum list | Node.js | SHA256 came from `SHASUMS256.txt`. |
| Official registry checksum | colorls | SHA256 identifies the `.gem`; RubyGems transitive dependencies are not fully locked. |
| GitHub release API digest | zoxide, Herdr, Neovim, bat, fd | SHA256 was verified from release API digest metadata, not a signature. |
| Official Git identity | Homebrew, Lazy/plugin checkouts | Homebrew tag `6.0.22` must resolve to commit `08e85c4e42f5d8f1ea17c36cb59cf61c2ccb26c3`; enabled Neovim checkouts must match repository `lazy-lock.json`; no publisher signatures were verified. |
| Mason package receipts | 11 Mason packages | The official registry evolves; each receipt must retain the expected Mason package name and the pinned version in its actual `source.id`. Registry release tags and registry archive checksums are not reproduction requirements. |
| GitHub asset digest | tree-sitter CLI | Official Linux x64 gzip 0.27.0 is verified before extraction; grammar revisions come from the locked nvim-treesitter checkout. |

Downloads are verified before extraction or execution. Archive members and links are checked for unsafe paths. Version roots are retained beneath the XDG data directory, and only installer-owned links in `~/.local/bin` may be replaced. Homebrew uses a user-local prefix with automatic updates disabled; bottles targeting the standard Linuxbrew prefix may be unavailable. Mason npm and Colorls RubyGem transitive dependencies are not wholly frozen. `win32yank.exe` remains unresolved Windows interop and is not implemented by the Linux profile.

## Manifest-related active versions

| Tool | Active version | Per-tool origin evidence |
|---|---:|---|
| zsh | 5.9.2 | not captured |
| git | 2.55.0 | not captured |
| curl | 8.21.0 | not captured |
| fzf | 0.74.2 | not captured |
| bat | 0.26.1 | not captured |
| fd | 10.4.2 | Pi agent-managed binary directory |
| ca-certificates | version not captured/unresolved | not captured |
| starship | 1.26.0 | not captured |
| atuin | 18.19.0 | not captured |
| zoxide | 0.10.0 | not captured |
| herdr | 0.7.5 | not captured |
| nvim | 0.12.4 | not captured |
| node | v22.23.1 | NVM |
| brew | 6.0.22 | not captured |
| win32yank.exe | version not captured/unresolved | not captured |
| colorls | 1.5.0 | not captured |

The aggregate command-resolution evidence showed that active commands resolved mostly through Homebrew. It did not establish a reliable Homebrew attribution for every individual command, so the table keeps unproven per-tool origins as `not captured`.

## Companion observed versions

These tools were observed on the workstation but are not manifest tools.

| Companion | Observed version | Origin evidence |
|---|---:|---|
| npm | 10.9.8 | not captured |
| ripgrep | 15.2.0 | Pi agent-managed binary directory |
| carapace | 1.7.3 | not captured |
| Ruby | 4.0.6 | not captured |
| Lazygit | 0.64.0 | not captured |
| tmux | 3.2a | not captured |
| Zellij | 0.44.3 | not captured |
| Warp Oz | v0.2026.09.09.08.26.stable_02 | manually installed on Windows |
| Hack Nerd Font Mono | presence confirmed; exact font version not captured | manually installed on Windows |

## APT state versus active commands

APT recorded `zsh` 5.8.1, `git` 2.34.1, and `curl` 7.81.0, with certificates installed. The APT packages for `fzf`, `bat`, and `fd-find` were absent because equivalent active commands came from other sources.

This distinction is material: package installation state does not prove which executable a shell resolves. Any reconciliation must record and review the executable selected by the environment and its `--version` output. Source URLs, checksums or signatures, activation order, and rollback remain unresolved evidence and require a separate review before any exact installation workflow is implemented.
