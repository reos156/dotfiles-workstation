# Install Windows prerequisites manually

Windows changes are deliberately outside automation. A human must review and perform every step.

## Checkpoint 1: WSL 2 and Ubuntu

1. Open Microsoft's WSL installation documentation: <https://learn.microsoft.com/windows/wsl/install>.
2. In an elevated PowerShell window, install WSL and an Ubuntu distribution using Microsoft's documented command.
3. Restart Windows if requested.
4. Launch Ubuntu once, choose a Linux username, and finish first-run setup.
5. In PowerShell, run `wsl --list --verbose`; confirm the intended Ubuntu distribution by name and verify that it reports WSL version `2`.
6. If more than one Ubuntu or migration-related distribution appears, inspect which one contains the intended files and configuration before any destructive action. Do not run `wsl --unregister`, delete a distribution, or remove its virtual disk merely to resolve a duplicate name.

The dotfiles installer does not repair, migrate, restart, shut down, unregister, or delete WSL distributions. Diagnose unexpected WSL lifecycle failures separately before changing dotfiles.

Do not place a real username, distribution identifier, or Windows profile path in this bundle.

## Checkpoint 2: Warp for Windows

1. Download Warp from <https://www.warp.dev/>.
2. Review the publisher and installer signature.
3. Run the Windows installer manually.
4. Sign-in and cloud synchronization are optional. They are not required by this bundle.

## Checkpoint 3: Hack Nerd Font Mono

1. Obtain Hack Nerd Font from the Nerd Fonts project: <https://www.nerdfonts.com/font-downloads>.
2. Review the downloaded archive.
3. In Windows Explorer, select the desired Hack Nerd Font Mono files and choose **Install for all users** or **Install**.
4. Confirm `Hack Nerd Font Mono` appears in Windows font settings.

## Human approval boundary

Stop before running `ubuntu/install.sh`. The Ubuntu phase can request `sudo`, install packages, download recorded Git repositories, and optionally change the login shell. A human must approve those actions separately.
