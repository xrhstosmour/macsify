# macsify

Opinionated `macOS` configuration via shell scripts.

<!-- Screenshots coming soon -->

## Features

| Category | Details |
| -------- | ------- |
| Shell | `Fish` + `Starship` + `Atuin` |
| Terminal | `WezTerm` |
| Editors | `Helix`, `VS Code`, `DataGrip` |
| Window Manager | `AeroSpace` + `SwipeAeroSpace` + `DockDoor` |
| Development Languages | `Node.js`, `Python`, `Go`, `Java`, `Ruby`, `.NET` (via `mise`) |
| Keyboard | Remapping with persistence (`kbcs` for cheat sheet) |
| Shell Abbreviations | Custom aliases (`alcs` for cheat sheet) |
| Coding Agent Runtime | `Herdr` (`cacs` for cheat sheet) |
| Menu Bar | `Stege` |
| Clipboard | `Maccy` |
| Screenshots | `Flameshot` |
| Keep Awake | `Amphetamine` |
| Appearance | Dark mode + custom wallpapers |
| Security | `1Password` + Firewall + stealth mode enabled |
| Cleanup | `Mole` + Bloatware removal |
| Automation | Login and `Dock` items auto-configured |
| Authentication | `TouchID` for `sudo` |
| Progressive Web Applications | via `Google Chrome` |
| Packages | See [Brewfile](packages/Brewfile), [Additional Packages](packages/additional_packages.txt), and [Store applications](packages/store_applications_ids.txt) |

## Pre-Installation

1. Install `Xcode Command Line Tools` by typing `xcode-select --install` and follow the on-screen instructions.

2. Grant Terminal permissions (`System Settings → Privacy & Security`):

    - **Files & Folders** → Add Terminal
    - **Full Disk Access** → Add Terminal
    - **Accessibility** → Add Terminal

3. Customize packages and application lists:

    - Edit [packages/Brewfile](packages/Brewfile).
    - Edit [packages/additional_packages.txt](packages/additional_packages.txt).
    - Edit [packages/store_applications_ids.txt](packages/store_applications_ids.txt).

4. Configure `AI` models:

    - Edit [.config/agentic/models.txt](.config/agentic/models.txt) for all `OpenCode`, `Claude Code`, `Codex`, and `Copilot CLI` model assignments.

## Installation

```bash
./install.sh
```

### Agentic Setup Only

To pull just the shared `AI` config, agents, instructions, skills, commands, and hooks for `OpenCode`, `Claude Code`, `Codex`, and `Copilot CLI`, without the rest of macsify:

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

### Keyboard Configuration

**Modifier Keys** (`System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys`):

> Keys (left to right):
>
> - `Key 1` = Globe (`Apple`) / Control (`Windows/PC`)
> - `Key 2` = Control (`Apple`) / Super (`Windows/PC`)
> - `Key 3` = Option (`Apple`) / Alt (`Windows/PC`)

*Apple keyboards (internal/external):*

| Key | Mapping |
| ---- | ------- |
| Globe | Command |
| Control | Option |
| Option | Control |

*Non-Apple keyboards (use `Windows/PC` mode, not `macOS`):*

| Key | Mapping |
| ---- | ------- |
| Control | Command |
| Command | Option |
| Option | Control |

### Display

`System Settings → Displays`:

- Disable **`True Tone`**

### Calendar

`System Settings → Internet Accounts`:

- Add your accounts (`iCloud`, `Google`, etc.) so events show up in the time widget's popup.

### `Finder`

Open `Finder` and configure sidebar:

- Remove: Recents, Shared, `iCloud`, `AirDrop`
- Add to Locations: `Home` folder
- Add to Favorites: `Developer` folder

### `1Password`

- [Enable SSH key management](https://developer.1password.com/docs/ssh/get-started).
- [Enable commit signing](https://1password.com/blog/git-commit-signing).
- Configure keyboard shortcuts (`Settings → General → Keyboard Shortcuts`):
  - Autofill: `Key 2 + Shift + A`
  - Quick Access: `Key 2 + Shift + S`
  - Clear remaining shortcuts to avoid conflicts.

### `PWA`s

1. Open `Google Chrome` and visit:
   - [`Google Messages`](https://messages.google.com/web)
   - [`Google Photos`](https://photos.google.com/)

2. For each site, go to `Chrome main menu → Cast, Save, and Share → Install Page as App...` and follow the on-screen instructions.

3. Enable `chrome://settings/content → Additional content settings → On-device site data → Allow sites to save data on your device`
