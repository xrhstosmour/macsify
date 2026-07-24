#!/bin/bash

# Function to create a symlink, replacing a stale real file or directory at the
# destination first, `ln -f` cannot unlink a non-empty directory.
# Usage:
#   create_symlink "$SOURCE_PATH" "$DESTINATION_PATH"
create_symlink() {
  local source_path="$1"
  local destination_path="$2"

  if [ -e "$destination_path" ] && [ ! -L "$destination_path" ]; then
    rm -rf "$destination_path"
  fi

  ln -sfn "$source_path" "$destination_path"
}
