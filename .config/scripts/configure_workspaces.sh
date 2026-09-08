
#!/bin/bash

# Catch exit signal (`CTRL` + `C`) to terminate the whole script.
trap "exit" INT

# Terminate script on error.
set -e

# Function to print monitor information.
# Usage:
#   get_monitor_info
get_monitor_info() {
    aerospace list-monitors
}


# Function to get the number of connected displays.
# Usage:
#   get_display_count
get_display_count() {
    aerospace list-monitors | wc -l | tr -d ' '
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
        last_count=$(get_display_count)
        if [ "$last_count" -eq "$expected_count" ]; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep "$delay"
    done

    echo "Warning: AeroSpace still reports $last_count monitor(s), expected $expected_count, proceeding anyway." >&2
}


# Function to check if `MacBook` built-in display is present.
# Returns `true` if found, `false` otherwise.
# Usage:
#   has_builtin_display
has_builtin_display() {
        # Built-in displays usually have names like "Built-in", "Color LCD", etc.
    if aerospace list-monitors | grep -qi "built-in\|color lcd\|liquid retina"; then
        echo "true"
    else
        echo "false"
    fi
}


# Function to distribute 10 workspaces evenly across all connected displays.
# If there is a remainder, it is assigned to the built-in display, if present,
# otherwise distributed round-robin to external displays.
#
# Usage:
#   configure_workspaces <display_count> <has_builtin>
configure_workspaces() {
    local total_displays=$1
    local has_builtin=$2

    if [ "$total_displays" -eq 0 ]; then
        return 1
    fi

    # Get monitor IDs.
    local monitor_ids=($(aerospace list-monitors | awk '{print $1}'))

    # Clean up any extra workspaces (keep only 1-10).
    # Move windows from extra workspaces to workspace 10, then empty workspaces auto-close.
    for workspace in $(aerospace list-workspaces --all); do
        if [ "$workspace" -gt 10 ]; then
            # Move all windows from this workspace to workspace 10.
            for window_id in $(aerospace list-windows --workspace "$workspace" 2>/dev/null | awk '{print $1}'); do
                aerospace move-node-to-workspace 10 --window-id "$window_id" 2>/dev/null || true
            done
        fi
    done

    # Identify built-in monitor if present.
    local builtin_monitor=""
    local external_monitors=()

    if [ "$has_builtin" = "true" ]; then
        for monitor_id in "${monitor_ids[@]}"; do
            local monitor_name=$(aerospace list-monitors | grep "^$monitor_id " | cut -d'|' -f2 | tr -d ' ')
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

    # Distribute to external monitors first.
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
}


# Main execution function.
# Prints current monitor setup, computes workspace distribution, and applies it.
# Usage:
#   main
main() {
    local expected_display_count=$1

    wait_for_expected_display_count "$expected_display_count"

    local display_count=$(get_display_count)
    local has_builtin=$(has_builtin_display)

    configure_workspaces "$display_count" "$has_builtin"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
