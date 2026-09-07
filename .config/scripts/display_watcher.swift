import CoreGraphics
import Foundation

// Debounces reconfiguration callbacks, `CoreGraphics` fires once per display
// involved in a single physical connect/disconnect, into a single reload.
var pendingReloadWorkItem: DispatchWorkItem?

// Tracks the in-flight reload subprocess so overlapping display events don't
// launch a second `aerospace` redistribution against an already-stale layout.
var runningReloadTask: Process?

// Function to run `reload_environment.sh` after a short debounce window.
// Usage:
//   scheduleReload()
func scheduleReload() {
    pendingReloadWorkItem?.cancel()

    let workItem = DispatchWorkItem {
        if let runningReloadTask, runningReloadTask.isRunning {
            return
        }

        let reloadScriptPath = NSHomeDirectory() + "/.config/scripts/reload_environment.sh"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [reloadScriptPath]

        // `launchd` jobs run with a minimal `PATH` that does not include `Homebrew`'s
        // bin directory, so `aerospace` would not resolve without this.
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
        task.environment = environment

        do {
            try task.run()
            runningReloadTask = task
        } catch {
            let message = "Failed to launch reload_environment.sh: \(error)\n"
            FileHandle.standardError.write(message.data(using: .utf8)!)
        }
    }

    pendingReloadWorkItem = workItem
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.5, execute: workItem)
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
