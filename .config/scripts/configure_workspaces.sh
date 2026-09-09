
#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Function to log a message to `stderr`, captured by the `DisplayWatcher`
# `LaunchAgent`'s `StandardErrorPath` (`~/Library/Logs/DisplayWatcher.log`), so a
# boot-time run's monitor snapshot and distribution decisions stay diagnosable
# after the fact instead of only reproducible by guesswork.
# Usage:
#   log <message>
log() {
    echo "[configure_workspaces] $1" >&2
}


# Function to take a single snapshot of `aerospace list-monitors` output. Every
# other monitor-derived value in this script, display count, built-in
# presence, monitor IDs and names, is computed from this ONE snapshot, never
# by calling `aerospace list-monitors` again mid-run. Separate calls can
# disagree with each other while the display set is still settling, exactly
# the boot-time race (lid closed, externals still negotiating) this script
# exists to handle, and disagreement here is what let a stray workspace
# beyond 10 survive uncorrected.
# Usage:
#   get_monitor_snapshot
get_monitor_snapshot() {
    aerospace list-monitors
}


# Function to get the number of connected displays from a monitor snapshot.
# Usage:
#   get_display_count <snapshot>
get_display_count() {
    local snapshot=$1
    if [ -z "$snapshot" ]; then
        echo 0
        return
    fi
    echo "$snapshot" | wc -l | tr -d ' '
}


# Function to poll `AeroSpace`'s own monitor count until it matches the
# expected count, or a bounded timeout elapses. `AeroSpace`'s internal
# monitor detection can lag behind the `CoreGraphics` event that triggers
# this script, catching only some of a batch of connected/disconnected
# displays would otherwise misassign all 10 workspaces onto too few monitors.
# The ~3s bound (10 attempts x 0.3s) was measured against real reconnect
# latency during testing, don't shrink it without re-verifying live.
# Usage:
#   wait_for_expected_display_count <expected_count>
wait_for_expected_display_count() {
    local expected_count=$1

    if [ -z "$expected_count" ]; then
        return 0
    fi

    if ! [[ "$expected_count" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    local attempt=0
    local max_attempts=10
    local delay=0.3
    local last_count

    while [ "$attempt" -lt "$max_attempts" ]; do
        last_count=$(get_display_count "$(get_monitor_snapshot)")
        if [ "$last_count" -eq "$expected_count" ]; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep "$delay"
    done

    log "Warning: AeroSpace still reports $last_count monitor(s), expected $expected_count, proceeding anyway."
}


# Function to check if `MacBook` built-in display is present in a monitor
# snapshot. Returns `true` if found, `false` otherwise.
# Usage:
#   has_builtin_display <snapshot>
has_builtin_display() {
    local snapshot=$1
    # Built-in displays usually have names like "Built-in", "Color LCD", etc.
    if echo "$snapshot" | grep -qi "built-in\|color lcd\|liquid retina"; then
        echo "true"
    else
        echo "false"
    fi
}


# Function to clean up any workspace beyond 10. `AeroSpace` only reaps a
# workspace, drops it from `list-workspaces --all`, on an actual focus
# transition away from it, not merely once it has zero windows (verified
# live: emptying a stray workspace alone left it listed forever, a
# `workspace <other>` switch-away is what actually reaps it).
#
# Monitor OWNERSHIP of a workspace and which workspace is currently VISIBLE
# on a monitor are two different things in `AeroSpace`. The distribution loop
# in `configure_workspaces` only reassigns ownership for workspaces 1-10, it
# never touches a stray workspace's ownership, so a stray created earlier can
# still be visible on its original owning monitor even after distribution
# runs (verified live). Switching away from it must land on a workspace
# already owned by that SAME monitor, never a hardcoded one (e.g. always
# workspace 10): a different monitor can legitimately own that number, and
# switching to it there would steal it away, which is exactly what broke the
# 1-5 / 6-10 split the first time this was tried.
# Usage:
#   cleanup_stray_workspaces <originally_focused> <monitor_id>...
cleanup_stray_workspaces() {
    local originally_focused=$1
    shift
    local monitor_ids=("$@")
    local stray_workspaces=()

    for workspace in $(aerospace list-workspaces --all); do
        if [ "$workspace" -gt 10 ]; then
            stray_workspaces+=("$workspace")
            log "found stray workspace $workspace, cleaning up"

            # Find which monitor, if any, currently shows this stray workspace.
            local owning_monitor=""
            for monitor_id in "${monitor_ids[@]}"; do
                local visible_workspace
                visible_workspace=$(aerospace list-workspaces --monitor "$monitor_id" --visible 2>/dev/null || true)
                if [ "$visible_workspace" = "$workspace" ]; then
                    owning_monitor="$monitor_id"
                    break
                fi
            done

            # Pick a replacement already owned by that same monitor so switching
            # to it cannot reassign ownership of a workspace some other monitor
            # legitimately holds.
            local replacement=""
            if [ -n "$owning_monitor" ]; then
                for candidate in $(aerospace list-workspaces --monitor "$owning_monitor" 2>/dev/null); do
                    if [[ "$candidate" =~ ^[0-9]+$ ]] && [ "$candidate" -le 10 ] && [ "$candidate" != "$workspace" ]; then
                        replacement="$candidate"
                        break
                    fi
                done
            fi

            # Not currently visible anywhere, any real workspace works to force
            # the switch-away, prefer what was originally focused.
            if [ -z "$replacement" ]; then
                replacement=10
                if [[ "$originally_focused" =~ ^[0-9]+$ ]] && [ "$originally_focused" -le 10 ] && [ "$originally_focused" != "$workspace" ]; then
                    replacement=$originally_focused
                fi
            fi

            # Move all windows from this workspace to the replacement, so they
            # land on the same monitor the stray was actually showing on.
            for window_id in $(aerospace list-windows --workspace "$workspace" 2>/dev/null | awk '{print $1}'); do
                aerospace move-node-to-workspace "$replacement" --window-id "$window_id" 2>/dev/null || true
            done

            log "flushing stray workspace $workspace via $replacement"
            aerospace workspace "$workspace" 2>/dev/null || true
            aerospace workspace "$replacement" 2>/dev/null || true
        fi
    done

    if [ "${#stray_workspaces[@]}" -eq 0 ]; then
        return 0
    fi

    # `AeroSpace` reaps the workspace shortly after the switch-away
    # completes, not synchronously with it, give it a moment so
    # `list-workspaces --all` is already clean by the time this script
    # exits rather than clean up moments later.
    sleep 0.3

    log "flushed stray workspace(s): ${stray_workspaces[*]}"
}


# Function to distribute 10 workspaces evenly across all connected displays.
# If there is a remainder, it is assigned to the built-in display, if present,
# otherwise distributed round-robin to external displays.
#
# Usage:
#   configure_workspaces <snapshot> <display_count> <has_builtin> <originally_focused>
configure_workspaces() {
    local snapshot=$1
    local total_displays=$2
    local has_builtin=$3
    local originally_focused=$4

    if [ "$total_displays" -eq 0 ]; then
        return 1
    fi

    # Get monitor IDs from the snapshot `main` already took, not a fresh query.
    local monitor_ids=($(echo "$snapshot" | awk '{print $1}'))

    log "snapshot: $total_displays display(s), has_builtin=$has_builtin, monitor_ids=${monitor_ids[*]}"

    # Identify built-in monitor if present.
    local builtin_monitor=""
    local external_monitors=()

    if [ "$has_builtin" = "true" ]; then
        for monitor_id in "${monitor_ids[@]}"; do
            local monitor_name=$(echo "$snapshot" | grep "^$monitor_id " | cut -d'|' -f2 | tr -d ' ')
            if [[ "$monitor_name" =~ Built-in|Retina|LCD ]]; then
                builtin_monitor="$monitor_id"
            else
                external_monitors+=("$monitor_id")
            fi
        done
    else
    # All monitors are external when lid is closed.
        external_monitors=("${monitor_ids[@]}")
    fi

    # Calculate distribution and split 10 workspaces evenly, give remainder to built-in.
    local workspaces_per_display=$((10 / total_displays))
    local remainder=$((10 % total_displays))
    local workspace=1

    # Distribute to external monitors first. This also evicts any stray
    # workspace beyond 10 that a currently connected monitor may still be
    # showing, since every real monitor is forced onto a workspace in 1-10.
    for monitor_id in "${external_monitors[@]}"; do
        for i in $(seq 1 $workspaces_per_display); do
            aerospace move-workspace-to-monitor --workspace "$workspace" "$monitor_id"
            workspace=$((workspace + 1))
        done
    done

    # Distribute to built-in monitor.
    if [ -n "$builtin_monitor" ]; then
        local builtin_count=$((workspaces_per_display + remainder))
        if [ "$builtin_count" -gt 0 ]; then
            for i in $(seq 1 $builtin_count); do
                aerospace move-workspace-to-monitor --workspace "$workspace" "$builtin_monitor"
                workspace=$((workspace + 1))
            done
        fi
    else
    # If no built-in, distribute remainder to external monitors.
        if [ "$remainder" -gt 0 ]; then
            for i in $(seq 1 $remainder); do
                local monitor_index=$(((i - 1) % ${#external_monitors[@]}))
                local monitor_id="${external_monitors[$monitor_index]}"
                aerospace move-workspace-to-monitor --workspace "$workspace" "$monitor_id"
                workspace=$((workspace + 1))
            done
        fi
    fi

    log "distributed workspaces 1-$((workspace - 1)) across ${#monitor_ids[@]} monitor(s)"

    cleanup_stray_workspaces "$originally_focused" "${monitor_ids[@]}"
}


# Main execution function.
# Waits for `AeroSpace`'s monitor count to settle, takes a single monitor
# snapshot, computes display count and built-in presence from it, and applies
# the resulting workspace distribution. Captures the focused workspace before
# any of that runs, `move-workspace-to-monitor` follows focus to whatever it
# just moved, so distribution itself shifts focus around, capturing this any
# later would restore the wrong workspace.
# Usage:
#   main
main() {
    local expected_display_count=$1

    wait_for_expected_display_count "$expected_display_count"

    local originally_focused
    originally_focused=$(aerospace list-workspaces --focused 2>/dev/null || true)

    local snapshot
    snapshot=$(get_monitor_snapshot)
    local display_count
    display_count=$(get_display_count "$snapshot")
    local has_builtin
    has_builtin=$(has_builtin_display "$snapshot")

    configure_workspaces "$snapshot" "$display_count" "$has_builtin" "$originally_focused"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
