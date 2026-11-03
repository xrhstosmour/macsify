#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
HERDR_APPLICATION_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$HERDR_APPLICATION_SCRIPT_DIRECTORY/../helpers/logs.sh"

# Installs the `Herdr` desktop app and sets up its community mods, run by
# `setup/agentic.sh`. The app has no `Homebrew` cask, so its own installer puts
# it in `~/Applications` and links `herdr-app` into `~/.local/bin`, which is the
# one place checked for it being installed.
HERDR_APPLICATION_BINARY="$HOME/.local/bin/herdr-app"
HERDR_APPLICATION_MODS_DIRECTORY="${HERDR_APPLICATION_HOME:-$HOME/.config/herdr-app}/mods"

# The installer, read on 2026-11-03 and pinned by its checksum, so a changed
# installer stops here instead of running unread. It still downloads the app
# build its release manifest names, checked against that manifest and the
# bundle's signature. Bump the checksum only after reading the new installer.
HERDR_APPLICATION_INSTALLER_URL="https://releases.herdr.dev/app/install.sh"
HERDR_APPLICATION_INSTALLER_SHA256="49e2b998ee311e131997447542869b99f888ef6c3cd4610abfaa97f4f44b52eb"

# Community mods, one per line as `repository commit mod-folder...`. Each commit
# is the one reviewed on 2026-11-03, a mod can run programs and read files, and
# `Herdr` does not review them. `herdr-space-folders` also writes
# `~/.config/herdr-space-folders.json`, outside its own folder. Bump a commit
# only after reading the diff. `tmux-prefix` is not here, it is vendored in
# `.config/herdr-app/mods/` with its own key bindings.
HERDR_APPLICATION_MODS=(
  "vytasgavelis/herdr-reviewer 424ca3e9cbe3e739df12e356a250c72612477fb5 reviewer"
  "rabeeh-ta/herdr-git-graph 2226f5733165667fb214aa3bdf78427fb29900c8 git-graph"
  "jankeesvw/herdr-space-folders 0f1bae881bd5053e607585d94e8cab2b94a8b0de space-folders"
  "NazzarenoGiannelli/herdr-roundup 1ee565326cb4ccde7ee872b451ef3fd468b62348 roundup roundup-dry"
  "CacaoRick/herdr-open-vscode 1dfa20974f6da63b195660b68dd120bed2412184 open-vscode"
)

# Never wait on a credentials prompt for a repository that moved or went private.
export GIT_TERMINAL_PROMPT=0

WORK_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$WORK_DIRECTORY"' EXIT

# A failed install leaves the mods to set up, they are plain files, and only
# their checks wait for the app.
if [ ! -x "$HERDR_APPLICATION_BINARY" ]; then
  log_info "Installing the 'Herdr' app..."
  installer="$WORK_DIRECTORY/install.sh"
  if ! curl -fsSL "$HERDR_APPLICATION_INSTALLER_URL" -o "$installer"; then
    log_warning "Could not download the 'Herdr' app installer, the app is skipped."
  elif ! printf '%s  %s\n' "$HERDR_APPLICATION_INSTALLER_SHA256" "$installer" | shasum -a 256 -c --status; then
    log_error "The 'Herdr' app installer changed since it was reviewed, the app is skipped, read it and bump the checksum in 'settings/herdr.sh'."
  elif ! sh "$installer"; then
    log_warning "The 'Herdr' app installer failed, the app is skipped."
  fi
fi
log_divider

mkdir -p "$HERDR_APPLICATION_MODS_DIRECTORY"

# Mods that were just installed or already there, all of them are checked below.
checked_folders=()

for entry in "${HERDR_APPLICATION_MODS[@]}"; do
  read -r repository commit folders <<<"$entry"
  clone_directory="$WORK_DIRECTORY/$(basename "$repository")"

  for folder in $folders; do
    checked_folders+=("$folder")

    if [ -d "$HERDR_APPLICATION_MODS_DIRECTORY/$folder" ]; then
      log_warning "'$folder' mod already installed, delete '$HERDR_APPLICATION_MODS_DIRECTORY/$folder' to reinstall."
      continue
    fi

    # Cloned on first need only, and checked out at the reviewed commit. One
    # failing mod must not stop the rest, so it is reported and skipped.
    if [ ! -d "$clone_directory" ]; then
      log_info "Fetching '$repository' at '${commit:0:7}'..."
      {
        git clone --quiet "https://github.com/$repository.git" "$clone_directory" &&
          git -C "$clone_directory" checkout --quiet "$commit"
      } || {
        rm -rf "$clone_directory"
        log_warning "Could not fetch '$repository', the '$folder' mod is skipped."
        continue
      }
    fi

    # Copied, never linked, `Herdr` does not reload a linked mod folder.
    log_info "Installing the '$folder' mod..."
    cp -R "$clone_directory/mods/$folder" "$HERDR_APPLICATION_MODS_DIRECTORY/$folder" || {
      log_warning "Could not copy the '$folder' mod, it is skipped."
      continue
    }
  done
done
log_divider

# Small patches to mods we do not own, in `.config/herdr-app/patches/`, named
# after the mod they change. `space-folders` drew the repo and branch after a
# space's name and `agents` the program name after an agent's, both only repeat
# what the icon and the tab already say. Each applies to the pinned commit or the
# app version it was made against, so a bump rechecks it. A mod that already
# carries a patch is left alone.
for patch_file in "$HERDR_APPLICATION_SCRIPT_DIRECTORY/../.config/herdr-app/patches/"*.patch; do
  patched_mod=$(basename "$patch_file" | cut -d. -f1)
  [ -d "$HERDR_APPLICATION_MODS_DIRECTORY/$patched_mod" ] || continue

  # The forward check comes first, a reverse check also passes on an unpatched file
  # when the patch only removes lines.
  if patch -p0 -N --dry-run -s -d "$HERDR_APPLICATION_MODS_DIRECTORY" <"$patch_file" &>/dev/null; then
    patch -p0 -N -s -d "$HERDR_APPLICATION_MODS_DIRECTORY" <"$patch_file"
    log_success "Applied the '$patched_mod' patch."
  elif patch -p0 -R --dry-run -s -d "$HERDR_APPLICATION_MODS_DIRECTORY" <"$patch_file" &>/dev/null; then
    log_info "The '$patched_mod' patch is already applied."
  else
    log_warning "The '$patched_mod' patch does not apply, the mod changed, update the patch."
  fi
done

# The vendored mods in `.config/herdr-app/mods/` are copied again on every run,
# so a rerun of `setup/agentic.sh` alone refreshes them after a merge.
VENDORED_MODS_DIRECTORY="$HERDR_APPLICATION_SCRIPT_DIRECTORY/../.config/herdr-app/mods"
for vendored_mod in tmux-prefix worktree-cleanup repository-sync tab-names; do
  checked_folders+=("$vendored_mod")
  mkdir -p "$HERDR_APPLICATION_MODS_DIRECTORY/$vendored_mod"
  cp -R "$VENDORED_MODS_DIRECTORY/$vendored_mod/." "$HERDR_APPLICATION_MODS_DIRECTORY/$vendored_mod/" || log_warning "Could not copy the '$vendored_mod' mod."
done

# Every mod is checked, installed ones included, once the app exists.
if [ -x "$HERDR_APPLICATION_BINARY" ]; then
  for folder in "${checked_folders[@]}"; do
    [ -d "$HERDR_APPLICATION_MODS_DIRECTORY/$folder" ] || continue
    "$HERDR_APPLICATION_BINARY" check "$HERDR_APPLICATION_MODS_DIRECTORY/$folder" || log_warning "'$folder' mod fails its check, 'Herdr' keeps it unloaded."
  done
else
  log_warning "Mod checks skipped, 'herdr-app' is not installed, run 'settings/herdr.sh' again once it is."
fi

log_success "'Herdr' app set up, switch to the 'workbench' layout once with 'ctrl-shift-l'."
