#!/bin/bash
# Claude Code SessionStart hook. Routes a new pane into a herdr space
# (workspace) that matches its git repo, instead of leaving it nested under
# whatever space it happened to be opened from. herdr's own workspaces are
# explicit containers, not auto-derived per repo, so a session started in a
# different repo than the current space's origin stays grouped with it,
# hiding it from the sidebar as its own space. herdr's socket API already
# supports moving a pane into a new or existing workspace without killing
# its underlying process (`pane.move`), so this routes via that existing
# API rather than patching herdr itself. Modeled on herdr's own managed
# ~/.claude/hooks/herdr-agent-state.sh hook for the stdin/env handling, kept
# as a separate script per that file's own header, which warns it gets
# overwritten on integration updates.
#
# herdr's public API doesn't expose git identity for ordinary workspaces
# (only ones created through its own worktree feature do), so this hook
# tracks repo/worktree-to-workspace mappings itself in
# ~/.config/herdr/workspace-router-map.json (shared with the OpenCode
# equivalent in opencode-context-guard.js), re-validating against the live
# workspace list on every run so a closed or renamed workspace doesn't leave
# a stale mapping behind. Resolves the pane's cwd via `pane.get` rather than
# the hook's own stdin payload, its `cwd` field isn't documented and herdr
# already tracks the real cwd per pane.
#
# Identity is the worktree's own root (`git rev-parse --show-toplevel`), not
# `--git-common-dir`: the common dir is shared by every linked worktree of a
# repo, so keying on it would merge separate worktrees, each usually a
# distinct, parallel unit of work, into one space. The toplevel differs per
# worktree, so each gets routed to its own space, while an ordinary (non-
# worktree) repo just gets its own root as before.
#
# Only routes panes that already belong to a live herdr pane running an
# agent session, a plain shell (e.g. a new fish tab with no repository)
# never triggers a `SessionStart` hook at all, and a pane whose cwd isn't a
# git repo exits immediately below, so opening a bare terminal never creates
# or touches any space.
set -eu

action="${1:-}"
hook_input_file="$(mktemp "${TMPDIR:-/tmp}/herdr-workspace-router.XXXXXX")" || exit 0
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

[ "$action" = "session" ] || exit 0
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

HERDR_PANE_ID="$HERDR_PANE_ID" HERDR_SOCKET_PATH="$HERDR_SOCKET_PATH" \
  HERDR_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY'
import json
import os
import random
import socket
import subprocess
import time

pane_id = os.environ.get("HERDR_PANE_ID")
socket_path = os.environ.get("HERDR_SOCKET_PATH")
hook_input_file = os.environ.get("HERDR_HOOK_INPUT_FILE")

if not pane_id or not socket_path:
    raise SystemExit(0)

hook_input = {}
if hook_input_file:
    try:
        with open(hook_input_file, encoding="utf-8") as handle:
            content = handle.read()
        if content.strip():
            hook_input = json.loads(content)
    except Exception:
        raise SystemExit(0)

if hook_input.get("hook_event_name") != "SessionStart":
    raise SystemExit(0)
if hook_input.get("agent_id"):
    raise SystemExit(0)


def rpc(method, params):
    request_id = f"herdr:workspace-router:{int(time.time() * 1000)}:{random.randrange(1_000_000):06d}"
    request = {"id": request_id, "method": method, "params": params}
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(1.0)
    client.connect(socket_path)
    client.sendall((json.dumps(request) + "\n").encode())
    buffer = b""
    while not buffer.endswith(b"\n"):
        chunk = client.recv(65536)
        if not chunk:
            break
        buffer += chunk
    client.close()
    response = json.loads(buffer.decode())
    if "error" in response:
        raise RuntimeError(response["error"].get("message", "herdr rpc error"))
    return response["result"]


try:
    pane_result = rpc("pane.get", {"pane_id": pane_id})
    pane = pane_result["pane"]
    current_workspace_id = pane["workspace_id"]
    cwd = pane.get("foreground_cwd") or pane.get("cwd")

    workspace_result = rpc("workspace.list", {})
    workspaces = {w["workspace_id"]: w for w in workspace_result["workspaces"]}
except Exception:
    raise SystemExit(0)

if current_workspace_id not in workspaces:
    raise SystemExit(0)
if not isinstance(cwd, str) or not cwd:
    raise SystemExit(0)

try:
    git_result = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--path-format=absolute", "--show-toplevel"],
        capture_output=True,
        text=True,
        timeout=2,
    )
except Exception:
    raise SystemExit(0)
if git_result.returncode != 0:
    raise SystemExit(0)
worktree_root = git_result.stdout.strip()
if not worktree_root:
    raise SystemExit(0)
repo_name = os.path.basename(worktree_root) or "workspace"

map_path = os.path.expanduser("~/.config/herdr/workspace-router-map.json")
os.makedirs(os.path.dirname(map_path), exist_ok=True)

# A plain `mkdir` is atomic on POSIX (fails with EEXIST if another process
# already holds it), so this doubles as a portable cross-process mutex with
# no extra dependency. Used instead of fcntl.flock so the lock is
# interchangeable with the OpenCode/Node side of this same router
# (opencode-context-guard.js), which has no flock equivalent available.
# If the holder is killed before its `finally` block removes the directory,
# the lock would otherwise wedge every future run forever, so a lock older
# than the critical section could ever legitimately take is force-cleared.
lock_path = map_path + ".lock"
lock_stale_seconds = 15
acquired = False
for _ in range(50):
    try:
        os.mkdir(lock_path)
        acquired = True
        break
    except FileExistsError:
        try:
            age = time.time() - os.stat(lock_path).st_mtime
        except FileNotFoundError:
            age = 0
        if age > lock_stale_seconds:
            try:
                os.rmdir(lock_path)
            except OSError:
                pass
            continue
        time.sleep(0.02)
if not acquired:
    raise SystemExit(0)

try:
    try:
        with open(map_path, encoding="utf-8") as handle:
            content = handle.read()
        repo_map = json.loads(content) if content.strip() else {}
    except Exception:
        repo_map = {}

    mapped_workspace_id = repo_map.get(worktree_root)
    if mapped_workspace_id not in workspaces:
        # Clears a stale mapping the same way as no mapping at all, a closed
        # or renamed workspace must not leave this repo permanently stuck.
        mapped_workspace_id = None
    destination = None

    if mapped_workspace_id and mapped_workspace_id != current_workspace_id:
        destination = {"type": "new_tab", "workspace_id": mapped_workspace_id}
    elif not mapped_workspace_id:
        current = workspaces[current_workspace_id]
        if current.get("pane_count") == 1 and current.get("tab_count") == 1:
            repo_map[worktree_root] = current_workspace_id
        else:
            destination = {
                "type": "new_workspace",
                "label": repo_name,
                "tab_label": None,
            }

    if destination is not None:
        try:
            move_response = rpc(
                "pane.move",
                {"pane_id": pane_id, "destination": destination},
            )
            move_result = move_response.get("move_result", {})
        except Exception:
            move_result = None
        if move_result:
            resolved_workspace_id = move_result.get("pane", {}).get("workspace_id")
            created_workspace = move_result.get("created_workspace")
            if created_workspace:
                resolved_workspace_id = created_workspace.get(
                    "workspace_id", resolved_workspace_id
                )
            if resolved_workspace_id:
                repo_map[worktree_root] = resolved_workspace_id

    with open(map_path, "w", encoding="utf-8") as handle:
        json.dump(repo_map, handle, indent=2, sort_keys=True)
        handle.write("\n")
except Exception:
    pass
finally:
    try:
        os.rmdir(lock_path)
    except Exception:
        pass
PY
