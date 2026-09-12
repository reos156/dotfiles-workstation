# Configure Warp manually for Ubuntu on WSL

Use this checklist after completing [PREREQUISITES.md](PREREQUISITES.md). The example file is a review template, not an import script.

## Create the WSL profile

1. Open Warp **Settings**.
2. Select the Ubuntu WSL distribution discovered by Warp. Do not paste a machine-specific executable or profile path from another computer.
3. Set the starting directory to the Linux home (`~`) or leave Warp's distribution default.
4. Keep the launch command distribution-independent. Prefer Warp's native WSL profile selection over a command containing a Windows user directory.
5. Open a tab and confirm `printf '%s\n' "$HOME"` reports the new Ubuntu user's home.

## Render the portable shell appearance

Zsh and Starship own the portable Powerline layout. Warp is one supported rendering example; any terminal can render the same prompt when it provides truecolor, the configured Nerd Font glyphs, and a shell-driven prompt surface.

1. Set the terminal font to **Hack Nerd Font Mono**.
2. Select the included `catppuccin-mocha.yaml` theme. If Warp requires manual theme installation, follow Warp's current custom-theme documentation and copy only that theme file to the location Warp documents.
3. Set Warp's **Input type** to **Shell (PS1)** so the Zsh/Starship prompt is rendered instead of visually replaced by a native input surface.
4. Compare settings against [`warp/settings.example.yaml`](warp/settings.example.yaml). Transcribe only settings available in the installed Warp version.
5. Reopen the Ubuntu tab after installation or run `exec zsh -l`.
6. Use [`../ubuntu/config/starship.toml`](../ubuntu/config/starship.toml) as the concrete prompt reference. Its Catppuccin Mocha Powerline chain shows OS/user, directory, contextual Git and runtime modules, Docker context, and time before the second-line prompt character.
7. Accept the result only when the private-use separators/icons, colored segment backgrounds, and structure are visible and `printf '%s\n' "$SHELL"`, `command -v zsh`, and `alias ls` report the configured shell and alias.

These are manual rendering settings, not installer actions. The repository does not write Warp settings, Windows settings, fonts, or terminal themes.

## Safety notes

- Do not copy Warp account, telemetry, workspace, launch-history, or session files.
- Do not copy a complete Warp settings database from another machine.
- Do not enable cloud synchronization merely to replicate this bundle.
- Windows installation and configuration remain human-operated; no PowerShell automation is supplied.
