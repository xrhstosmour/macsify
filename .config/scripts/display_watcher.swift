import CoreGraphics
import Foundation

// Debounces reconfiguration callbacks, `CoreGraphics` fires once per display
// involved in a single physical connect/disconnect, into a single reload.
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
// contexts (the `CoreGraphics` callback thread, the debounce work item, and
// `Process.terminationHandler`'s arbitrary thread), which would race.
let reloadQueue = DispatchQueue(label: "com.macsify.display-watcher.reload")

// Function to count currently active, non-mirrored displays via `CoreGraphics`,
// independent of `AeroSpace`'s own (possibly lagging) monitor detection.
// Mirrored secondary displays are excluded, `AeroSpace` counts logical
// monitors, not every physical panel in a mirror set. Returns `nil` if
// `CoreGraphics` fails to report the active display list.
// Usage:
//   activeDisplayCount()
func activeDisplayCount() -> Int? {
    var displayCount: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &displayCount) == .success else {
        return nil
    }

    var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
    guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
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
            // between this `CoreGraphics` callback and `AeroSpace`'s own monitor list.
            // Omitted entirely if `CoreGraphics` couldn't report a count, preserving
            // the no-wait behavior rather than forwarding a bogus zero.
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

// Callback invoked by `CoreGraphics` on any display reconfiguration. Only physical
// connect/disconnect (`addFlag`/`removeFlag`) triggers a reload, resolution or
// mirroring changes on already-connected displays are ignored.
let reconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, _ in
    if flags.contains(.addFlag) || flags.contains(.removeFlag) {
        scheduleReload()
    }
}

CGDisplayRegisterReconfigurationCallback(reconfigurationCallback, nil)

// Block forever, `CoreGraphics` delivers the callback on this thread's run loop.
CFRunLoopRun()
