#!/usr/bin/env bash
# Records your approval of one test workflow tree that mentions a deploy word, like a throwaway test environment, in the trust file of `lib.sh`, so `green-git.sh tests` and `green-respond.sh dispatch` run it from then on until any of its files changes.
# Kept apart from those scripts and on no allow list, so `claude/settings.json` asks you before every run, also in auto mode, an agent never approves a workflow itself. Run it only with the line an exit 5 printed, after reading the files and lines it showed.
# It replaces the older line of the same repository and workflow, through a temporary file in the same folder so a reader never sees half a file, and under a lock folder so two approvals at once never drop each other's line.
#
# Usage: green-trust.sh <owner/repo> .github/workflows/<file> <fingerprint>

set -e

# shellcheck source=SCRIPTDIR/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ $# -ne 3 ]; then
  echo "usage: green-trust.sh <owner/repo> .github/workflows/<file> <fingerprint>" >&2
  exit 2
fi
line="$1 $2 $3"
if ! [[ $line =~ $trust_line_pattern ]]; then
  echo "invalid trust line: $line" >&2
  exit 2
fi

directory="$(dirname "$trust_file")"
mkdir -p "$directory"
# `mkdir` is atomic and needs nothing macOS lacks, unlike `flock`. A lock left by a killed run is reported, never broken, so a second writer never races a live one.
lock="$trust_file.lock"
if ! mkdir "$lock" 2>/dev/null; then
  echo "$lock exists, another green-trust.sh is running, or remove it if none is" >&2
  exit 1
fi
trap 'rmdir "$lock"' EXIT
if [ -e "$trust_file" ] || [ -L "$trust_file" ]; then
  require_trust_file
fi
temporary="$(mktemp "$directory/trusted-workflows.XXXXXX")"
if [ -f "$trust_file" ]; then
  awk -v repository="$1" -v path="$2" '!($1 == repository && $2 == path)' "$trust_file" >"$temporary"
fi
echo "$line" >>"$temporary"
mv "$temporary" "$trust_file"
echo "trusted: $line"
