import AppKit
import CoreGraphics

// Debounces reconfiguration callbacks, more than one screen notification can
// fire for a single physical connect/disconnect, into a single reload.
var pendingReloadWorkItem: DispatchWorkItem?

// Tracks the in-flight reload subprocess so overlapping display events don't
// launch a second `aerospace` redistribution against an already-stale layout.
var runningReloadTask: Process?

// Set when a display event arrives while a reload is already running, so its
// request isn't silently dropped, the in-flight task's completion re-triggers
// a reload instead.
var reloadPendingAgain = false

// Serializes every read/write of `pendingReloadWorkItem`, `runningReloadTask`,
// and `reloadPendingAgain`, they're otherwise touched from three uncoordinated
// contexts (the notification handler, the debounce work item, and
// `Process.terminationHandler`'s arbitrary thread), which would race.
let reloadQueue = DispatchQueue(label: "com.macsify.display-watcher.reload")

// Function to list currently active display IDs via `CoreGraphics`. Returns
// `nil` if `CoreGraphics` fails to report the active display list.
// Usage:
//   activeDisplayIDs()
func activeDisplayIDs() -> [CGDirectDisplayID]? {
    var displayCount: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &displayCount) == .success else {
        return nil
    }

    var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
    guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
        return nil
    }

    return displayIDs
}

// Function to count currently active, non-mirrored displays, independent of
// `AeroSpace`'s own (possibly lagging) monitor detection. Mirrored secondary
// displays are excluded, `AeroSpace` counts logical monitors, not every
// physical panel in a mirror set. Returns `nil` if `CoreGraphics` fails to
// report the active display list.
// Usage:
//   activeDisplayCount()
func activeDisplayCount() -> Int? {
    guard let displayIDs = activeDisplayIDs() else {
        return nil
    }

    return displayIDs.filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }.count
}

// Function to run `reload_environment.sh` after a short debounce window.
// Usage:
//   scheduleReload()
func scheduleReload() {
    reloadQueue.async {
        pendingReloadWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            if let runningReloadTask, runningReloadTask.isRunning {
                reloadPendingAgain = true
                return
            }

            let reloadScriptPath = NSHomeDirectory() + "/.config/scripts/reload_environment.sh"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            // Pass the live display count so the reload script can wait out any lag
            // between this notification and `AeroSpace`'s own monitor list. Omitted
            // entirely if `CoreGraphics` couldn't report a count, preserving the
            // no-wait behavior rather than forwarding a bogus zero.
            if let count = activeDisplayCount() {
                task.arguments = [reloadScriptPath, String(count)]
            } else {
                task.arguments = [reloadScriptPath]
            }

            // `launchd` jobs run with a minimal `PATH` that does not include `Homebrew`'s
            // bin directory, so `aerospace` would not resolve without this.
            var environment = ProcessInfo.processInfo.environment
            let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
            task.environment = environment

            // If another display event arrived while this reload was running, its
            // request was recorded above rather than dropped, run a follow-up reload.
            // Dispatched back onto `reloadQueue`, `terminationHandler` fires on an
            // arbitrary Foundation-owned thread, not this one.
            task.terminationHandler = { _ in
                reloadQueue.async {
                    if reloadPendingAgain {
                        reloadPendingAgain = false
                        scheduleReload()
                    }
                }
            }

            do {
                // Set before `run()` so the tracking variable is visible before the
                // process can possibly exit and fire `terminationHandler`.
                runningReloadTask = task
                try task.run()
            } catch {
                let message = "Failed to launch reload_environment.sh: \(error)\n"
                FileHandle.standardError.write(message.data(using: .utf8)!)
            }
        }

        pendingReloadWorkItem = workItem
        reloadQueue.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }
}

// `CGDisplayRegisterReconfigurationCallback` never fires on macOS Tahoe (26.x),
// a confirmed `CoreGraphics` framework regression: registration succeeds but the
// callback is never invoked, even in foreground GUI processes, not just headless
// ones. `NSApplication`'s screen-parameters notification is the documented
// working alternative on both Sequoia and Tahoe, but it requires an actual
// `NSApplication` run loop rather than a bare `CFRunLoopRun()`, hence the
// `AppKit` scaffolding below in place of a plain command-line entry point.
//
// The notification fires for any screen change, resolution and mirroring
// included, so a snapshot of the active display ID set is compared on each
// firing to isolate actual connects/disconnects: only a change in the set of
// IDs schedules a reload, a bare mode or mirroring change on an
// already-connected display does not.
var knownDisplayIDs = Set(activeDisplayIDs() ?? [])

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil,
    queue: .main
) { _ in
    guard let currentDisplayIDs = activeDisplayIDs() else {
        return
    }

    let currentSet = Set(currentDisplayIDs)
    if currentSet != knownDisplayIDs {
        knownDisplayIDs = currentSet
        scheduleReload()
    }
}

app.run()
