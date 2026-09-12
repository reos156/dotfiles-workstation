# Source Workstation Observed Baseline — 2026-09-11

## Status and scope

This versioned observed reference was captured from the source workstation on 2026-09-11. It records the active command versions observed in that environment; those versions may differ from installed APT package versions.

The baseline is a target/reference for a separately reviewed reconciliation. It is not proof of an installation source, release asset, checksum, or signature, and it is not an installer flag. The repository has no `install.sh` option that selects this profile.

No machine-specific executable paths are recorded here. A replay must verify both the resolved executable path and the command's reported version rather than infer the active tool from package-manager state alone.

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
