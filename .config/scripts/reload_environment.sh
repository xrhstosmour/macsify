#!/bin/bash

# Reload environment. `$1`, if given, is the live display count observed by
# the caller, forwarded so `configure_workspaces.sh` can wait out any lag
# between it and `AeroSpace`'s own monitor detection.
aerospace reload-config
aerospace flatten-workspace-tree
~/.config/scripts/configure_workspaces.sh "$1"
