# macsify

Opinionated `macOS` setup via shell scripts, plus a shared configuration for `AI` coding agents.

<!-- Screenshots coming soon -->

## Features

| Category | Details |
| -------- | ------- |
| Shell | `Fish` + `Starship` + `Atuin`, custom aliases |
| Terminal | `WezTerm` + `Herdr` multiplexer |
| Editors | `Helix`, `VS Code`, `DataGrip` |
| Window Manager | `AeroSpace` + `SwipeAeroSpace` + `DockDoor` |
| Development Languages | `Node.js`, `Python`, `Go`, `Java`, `Ruby`, `.NET` (via `mise`) |
| Mobile Development | `Flutter` + `Android` SDK + `Xcode` + emulators |
| AI Agents | Shared `OpenCode`, `Claude Code`, `Codex` and `Copilot CLI` configuration (agents, skills, commands, hooks, instructions), wired up by `setup/agentic.sh` |
| Keyboard | Remapping with persistence (`kbcs` for cheat sheet) |
| Utilities | `Stege` (menu bar), `Maccy` (clipboard), `Flameshot` (screenshots), `Amphetamine` (keep awake), `Obsidian` (notes) |
| Network | `NordVPN`, `Tailscale` |
| Version Control | `Gitify`, custom `Git` abbreviations |
| Appearance | Dark mode + custom wallpapers |
| Security | `1Password` + Firewall + stealth mode + `TouchID` for `sudo` |
| Cleanup | `Mole` + Bloatware removal |
| Automation | Login and `Dock` items auto-configured |
| Progressive Web Applications | via `Google Chrome` |
| Packages | See [Brewfile](packages/Brewfile), [Additional Packages](packages/additional_packages.txt), and [Store applications](packages/store_applications_ids.txt) |

## Installation

1. Install `Xcode Command Line Tools` with `xcode-select --install`.

2. Add Terminal to `System Settings → Privacy & Security`: **Files & Folders**, **Full Disk Access** and **Accessibility**.

3. Customize [packages/Brewfile](packages/Brewfile), [packages/additional_packages.txt](packages/additional_packages.txt), [packages/store_applications_ids.txt](packages/store_applications_ids.txt) and the `AI` model assignments in [.config/agentic/models.txt](.config/agentic/models.txt).

4. Run:

    ```bash
    ./install.sh
    ```

To pull only the shared `AI` configuration, without the rest of macsify:

```bash
mkdir -p ~/.config && cp -R .config/agentic ~/.config/ && bash setup/agentic.sh
```

`setup/agentic.sh` only wires up a tool if its `brew`/`cask` line in [`packages/Brewfile`](packages/Brewfile) is present and uncommented, so trim that file to the wanted `AI` tools first.

## Post-Installation

### App Permissions

`System Settings → Privacy & Security`:

| App | Full Disk Access | Accessibility | Screen Recording | Developer Tools |
| --- | ---------------- | ------------- | ---------------- | --------------- |
| `WezTerm` | ✓ | ✓ | | ✓ |
| `VS Code` | | | | ✓ |
| `AeroSpace` | | ✓ | | |
| `DockDoor` | | ✓ | ✓ | |
| `Flameshot` | | | ✓ | |
| `Google Drive` | | ✓ | | |
| `Maccy` | | ✓ | | |
| `SwipeAeroSpace` | | ✓ | | |
| `Stege` | | ✓ | | |

### Keyboard Modifier Keys

`System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys`, keys numbered left to right. Use `Windows/PC` mode on non-Apple keyboards, not `macOS`, where `Key 2` is `Super` and `Key 3` is `Alt`.

| Key | Apple keyboards | Non-Apple keyboards | Mapping |
| --- | --------------- | ------------------- | ------- |
| `Key 1` | Globe | Control | Command |
| `Key 2` | Control | Command | Option |
| `Key 3` | Option | Option | Control |

### Manual Settings

- `Displays`: disable **`True Tone`**.
- `Internet Accounts`: add your accounts (`iCloud`, `Google`, etc.) so events show up in the time widget's popup.
- `Finder` sidebar: remove Recents, Shared, `iCloud`, `AirDrop`, add the `Home` folder to Locations and the `Developer` folder to Favorites.
- `1Password`: [enable SSH key management](https://developer.1password.com/docs/ssh/get-started) and [commit signing](https://1password.com/blog/git-commit-signing), then in `Settings → General → Keyboard Shortcuts` set Autofill to `Key 2 + Shift + A`, Quick Access to `Key 2 + Shift + S` and clear the rest to avoid conflicts.
- `PWA`s: in `Google Chrome` open [`Google Messages`](https://messages.google.com/web) and [`Google Photos`](https://photos.google.com/), install each with `Chrome main menu → Cast, Save, and Share → Install Page as App...`, then enable `chrome://settings/content → Additional content settings → On-device site data → Allow sites to save data on your device`.
