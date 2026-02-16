# macify

Opinionated `macOS` configuration via shell scripts.

<!-- Screenshots coming soon -->

## Features

| Category | Details |
|----------|---------|
| Shell | `Fish` + `Starship` + `Atuin` |
| Terminal | `WezTerm` |
| Editors | `Helix`, `VS Code`, `DataGrip` |
| Window Manager | `AeroSpace` + `SwipeAeroSpace` + `AltTab` |
| Development Languages | `Node.js`, `Python`, `Go`, `Java`, `Ruby`, `.NET` (via `mise`) |
| Keyboard | Remapping with persistence (`kbcs` for cheat sheet) |
| Shell Abbreviations | Custom aliases (`alcs` for cheat sheet) |
| Display | Auto notch-hiding for `MacBook` Pro/Air |
| Clipboard | `Maccy` |
| Screenshots | `Flameshot` |
| Keep Awake | `Amphetamine` |
| Appearance | Dark mode + custom wallpapers |
| Security | `1Password` + Firewall + stealth mode enabled |
| Cleanup | `Mole` + Bloatware removal |
| Automation | Login and `Dock` items auto-configured |
| Authentication | `TouchID` for `sudo` |
| Packages | See [Brewfile](packages/Brewfile), [PWA](packages/pwa_applications.txt) and [Store applications](packages/store_applications_ids.txt) |

## Pre-Installation

1. Install `Xcode Command Line Tools` by typing `xcode-select --install` and follow the on-screen instructions.

2. Grant Terminal permissions (`System Settings → Privacy & Security`):

    - **Files & Folders** → Add Terminal
    - **Full Disk Access** → Add Terminal
    - **Accessibility** → Add Terminal

3. Customize packages and app lists:

- Edit [packages/Brewfile](packages/Brewfile).
- Edit [packages/pwa_applications.txt](packages/pwa_applications.txt).
- Edit [packages/store_applications_ids.txt](packages/store_applications_ids.txt).

## Installation

```bash
./install.sh
```

## Post-Installation

### App Permissions

`System Settings → Privacy & Security`:

| App | Full Disk Access | Accessibility | Screen Recording | Developer Tools |
|-----|:----------------:|:-------------:|:----------------:|:---------------:|
| `WezTerm` | ✓ | ✓ | | ✓ |
| `VS Code` | | | | ✓ |
| `AeroSpace` | | ✓ | | |
| `AltTab` | | ✓ | ✓ | |
| `Flameshot` | | | ✓ | |
| `Maccy` | | ✓ | | |
| `SwipeAeroSpace` | | ✓ | | |

### Keyboard Configuration

**Modifier Keys** (`System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys`):

> Keys (left to right):
>
> - `Key 1` = Globe (`Apple`) / Control (`Windows/PC`)
>   - `Key 2` = Control (`Apple`) / Super (`Windows/PC`)
>   - `Key 3` = Option (`Apple`) / Alt (`Windows/PC`)

*Apple keyboards (internal/external):*

| Key | Maps To |
|-----|---------|
| Globe | Command |
| Control | Option |
| Option | Control |

*Non-Apple keyboards (use `Windows/PC` mode, not `macOS`):*

| Key | Maps To |
|-----|---------|
| Control | Command |
| Command | Option |
| Option | Control |

**Shortcuts** (`System Settings → Keyboard → Keyboard Shortcuts`):

- **Mission Control** → Disable all (conflicts with `AeroSpace`)
- **Spotlight** → Enable only `Show Spotlight search` → `Key 2 + .`
- **Input Sources** → Enable only `Select previous input source` → `Key 2 + Space`

### Trackpad

`System Settings → Trackpad → More Gestures`:

- Disable **Swipe between full-screen applications** (conflicts with `SwipeAeroSpace`)

### Display

`System Settings → Displays`:

- Disable **`True Tone`**

`System Settings → Accessibility → Display`:

- Enable **Reduce motion**

### `Finder`

Open `Finder` and configure sidebar:

- Remove: Recents, Shared, `iCloud`, `AirDrop`
- Add to Locations: `/` (`root`), `Home` folder
- Add to Favorites: `Developer` folder

### `1Password`

- [Enable SSH key management](https://developer.1password.com/docs/ssh/get-started).
- [Enable commit signing](https://1password.com/blog/git-commit-signing).
- Configure keyboard shortcuts (`Settings → General → Keyboard Shortcuts`):
  - Autofill: `Key 2 + Shift + A`
  - Quick Access: `Key 2 + Shift + S`
  - Clear remaining shortcuts to avoid conflicts.
