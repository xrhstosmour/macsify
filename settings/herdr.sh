#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Constant variable of the scripts' working directory to use for relative paths.
HERDR_APPLICATION_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Import functions and flags.
source "$HERDR_APPLICATION_SCRIPT_DIRECTORY/../helpers/logs.sh"

# Sets up the `Herdr` desktop app's community mods, layout and worktrees link,
# run by `setup/agentic.sh`. The app itself is the `herdr-app` cask in
# `packages/base.Brewfile`, which links `herdr-app` into `Homebrew`'s binary
# directory, checked here by being on `PATH`.
HERDR_APPLICATION_BINARY="$(command -v herdr-app || true)"
HERDR_APPLICATION_HOME_DIRECTORY="${HERDR_APPLICATION_HOME:-$HOME/.config/herdr-app}"
HERDR_APPLICATION_MODS_DIRECTORY="$HERDR_APPLICATION_HOME_DIRECTORY/mods"

# Community mods, one per line as `repository commit mod-folder...`. Each commit
# is the one reviewed on 2026-11-03, a mod can run programs and read files, and
# `Herdr` does not review them. Bump a commit only after reading the diff.
# `tmux-prefix`, `space-folders`, `agents-compact` and `tabs-inline` are not here, they are
# vendored in `.config/herdr-app/mods/`, each header says where it came from, at
# which commit or app version, and what was changed, a bump diffs against that.
HERDR_APPLICATION_MODS=(
  "vytasgavelis/herdr-reviewer 424ca3e9cbe3e739df12e356a250c72612477fb5 reviewer"
  "rabeeh-ta/herdr-git-graph 2226f5733165667fb214aa3bdf78427fb29900c8 git-graph"
  "CacaoRick/herdr-open-vscode 1dfa20974f6da63b195660b68dd120bed2412184 open-vscode"
)

# Never wait on a credentials prompt for a repository that moved or went private.
export GIT_TERMINAL_PROMPT=0

WORK_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$WORK_DIRECTORY"' EXIT

# The mods are plain files, only their checks wait for the app.
mkdir -p "$HERDR_APPLICATION_MODS_DIRECTORY"

# `pull-request` replaced the `roundup` mods, and the install loop below never deletes a mod.
for former_mod in roundup roundup-dry; do
  rm -rf "${HERDR_APPLICATION_MODS_DIRECTORY:?}/$former_mod"
done

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

# The vendored mods in `.config/herdr-app/mods/` are copied again on every run,
# so a rerun of `setup/agentic.sh` alone refreshes them after a merge.
VENDORED_MODS_DIRECTORY="$HERDR_APPLICATION_SCRIPT_DIRECTORY/../.config/herdr-app/mods"
for vendored_mod in tmux-prefix space-folders agents-compact tabs-inline worktree-developer worktree-cleanup repository-sync tab-names pull-request; do
  checked_folders+=("$vendored_mod")
  mkdir -p "$HERDR_APPLICATION_MODS_DIRECTORY/$vendored_mod"
  cp -R "$VENDORED_MODS_DIRECTORY/$vendored_mod/." "$HERDR_APPLICATION_MODS_DIRECTORY/$vendored_mod/" || log_warning "Could not copy the '$vendored_mod' mod."
done

# The shipped `worktree` mod, behind the space menu's New worktree, puts checkouts
# in `~/.herdr/worktrees`, a constant in a mod the app replaces on every start, so
# that folder is linked to where worktrees live here, `git` records the real path.
# The folder button uses the `worktree-developer` clone, which names the real folder. A real folder already there
# is left alone, it may hold worktrees.
HERDR_WORKTREES_LINK="$HOME/.herdr/worktrees"
mkdir -p "$HOME/Developer/worktrees" "$HOME/.herdr"
if [ -L "$HERDR_WORKTREES_LINK" ] || [ ! -e "$HERDR_WORKTREES_LINK" ]; then
  ln -sfn "$HOME/Developer/worktrees" "$HERDR_WORKTREES_LINK"
else
  log_warning "'$HERDR_WORKTREES_LINK' is a real folder, move its worktrees to '$HOME/Developer/worktrees' and delete it to link it."
fi

# Every mod is checked, installed ones included, once the app exists.
if [ -x "$HERDR_APPLICATION_BINARY" ]; then
  for folder in "${checked_folders[@]}"; do
    [ -d "$HERDR_APPLICATION_MODS_DIRECTORY/$folder" ] || continue
    "$HERDR_APPLICATION_BINARY" check "$HERDR_APPLICATION_MODS_DIRECTORY/$folder" || log_warning "'$folder' mod fails its check, 'Herdr' keeps it unloaded."
  done
else
  log_warning "Mod checks skipped, 'herdr-app' is not installed, run 'settings/herdr.sh' again once it is."
fi

# The vendored mods only run as blocks of the active layout, so select it here.
# A running app owns `shared.json` and would overwrite an edit of it, so it gets
# `layout.switch`, a closed one reads the `layout` key from the file on start.
HERDR_APPLICATION_SHARED_FILE="$HERDR_APPLICATION_HOME_DIRECTORY/shared.json"
if [ -x "$HERDR_APPLICATION_BINARY" ] && pgrep -x Herdr >/dev/null; then
  "$HERDR_APPLICATION_BINARY" "do" layout.switch '{"name":"workbench"}' >/dev/null || log_warning "Could not switch to the 'workbench' layout, use 'ctrl-shift-l'."
elif [ -s "$HERDR_APPLICATION_SHARED_FILE" ]; then
  # Written to a copy first, so an invalid file is left as it was.
  { jq '.layout = "workbench"' "$HERDR_APPLICATION_SHARED_FILE" >"$WORK_DIRECTORY/shared.json" && mv "$WORK_DIRECTORY/shared.json" "$HERDR_APPLICATION_SHARED_FILE"; } || log_warning "Could not set the 'workbench' layout in '$HERDR_APPLICATION_SHARED_FILE', use 'ctrl-shift-l'."
else
  printf '{"layout":"workbench"}\n' >"$HERDR_APPLICATION_SHARED_FILE"
fi

log_success "'Herdr' app set up."
