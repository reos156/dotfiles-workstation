# Configure Warp manually for Ubuntu on WSL

Use this checklist after completing [PREREQUISITES.md](PREREQUISITES.md). The example file is a review template, not an import script.

## Create the WSL profile

1. Open Warp **Settings**.
2. Select the Ubuntu WSL distribution discovered by Warp. Do not paste a machine-specific executable or profile path from another computer.
3. Set the starting directory to the Linux home (`~`) or leave Warp's distribution default.
4. Keep the launch command distribution-independent. Prefer Warp's native WSL profile selection over a command containing a Windows user directory.
5. Open a tab and confirm `printf '%s\n' "$HOME"` reports the new Ubuntu user's home.

## Match the appearance

1. Set the terminal font to **Hack Nerd Font Mono**.
2. Select the included `catppuccin-mocha.yaml` theme. If Warp requires manual theme installation, follow Warp's current custom-theme documentation and copy only that theme file to the location Warp documents.
3. Compare settings against [`warp/settings.example.yaml`](warp/settings.example.yaml). Transcribe only settings available in the installed Warp version.

## Safety notes

- Do not copy Warp account, telemetry, workspace, launch-history, or session files.
- Do not copy a complete Warp settings database from another machine.
- Do not enable cloud synchronization merely to replicate this bundle.
- Windows installation and configuration remain human-operated; no PowerShell automation is supplied.
