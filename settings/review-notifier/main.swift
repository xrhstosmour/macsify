import AppKit
import UserNotifications

// Posts one macOS notification that opens a GitHub link when clicked, built by
// `setup/agentic.sh` into `~/Applications/ReviewNotifier.app` so the review and
// green pull request watchers need no package. `osascript` cannot do it, its
// notification runs nothing on a click. A click relaunches this app with no
// arguments, so the delegate must be set before the run loop starts, and the run
// loop must be `NSApplication`'s, a bare `RunLoop` never delivers the click.
//
// Usage: review-notifier <title> <message> <url> <group> [ok|bad|info]
// The status adds a picture on the right, a macOS banner has one app icon on the
// left, so a result that changes with each review can only be an attachment.
func statusImage(_ status: String) -> URL? {
    let marks = ["ok": ("checkmark", NSColor(red: 0.09, green: 0.50, blue: 0.24, alpha: 1)),
                 "bad": ("xmark", NSColor(red: 0.76, green: 0.19, blue: 0.18, alpha: 1)),
                 "info": ("text.bubble.fill", NSColor(red: 0.15, green: 0.39, blue: 0.79, alpha: 1))]
    guard let (symbol, color) = marks[status],
          let glyph = NSImage(systemSymbolName: "arrow.triangle.merge", accessibilityDescription: nil),
          let mark = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
    let size = NSSize(width: 256, height: 256)
    let image = NSImage(size: size)
    image.lockFocus()
    let tile = NSRect(x: 8, y: 8, width: 240, height: 240)
    NSGradient(starting: NSColor(red: 0.30, green: 0.32, blue: 0.94, alpha: 1), ending: NSColor(red: 0.16, green: 0.18, blue: 0.62, alpha: 1))?
        .draw(in: NSBezierPath(roundedRect: tile, xRadius: 54, yRadius: 54), angle: -60)
    func tinted(_ symbol: NSImage, _ tint: NSColor, in rect: NSRect) {
        let configured = symbol.withSymbolConfiguration(.init(pointSize: rect.height, weight: .bold)) ?? symbol
        let painted = NSImage(size: rect.size, flipped: false) { bounds in
            configured.draw(in: bounds)
            tint.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        painted.draw(in: rect)
    }
    tinted(glyph, .white, in: NSRect(x: 52, y: 52, width: 132, height: 132))
    let badge = NSRect(x: 150, y: 6, width: 100, height: 100)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: badge.insetBy(dx: -8, dy: -8)).fill()
    color.setFill()
    NSBezierPath(ovalIn: badge).fill()
    tinted(mark, .white, in: badge.insetBy(dx: 24, dy: 24))
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("review-notifier-\(UUID().uuidString).png")
    return (try? png.write(to: file)) == nil ? nil : file
}

final class Delegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Only a GitHub address is opened, whatever the posting process passed.
        if let text = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: text), url.scheme == "https", url.host == "github.com" {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
        exit(0)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

let delegate = Delegate()
let center = UNUserNotificationCenter.current()
center.delegate = delegate
let arguments = Array(CommandLine.arguments.dropFirst())

// Never wait on a person, a first run can sit on the permission prompt and the
// script that called this app is waiting for it. A click launch gives up the same way.
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(0) }

if arguments.count == 4 || arguments.count == 5 {
    let (title, message, url, group) = (arguments[0], arguments[1], arguments[2], arguments[3])
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        guard granted else {
            FileHandle.standardError.write(Data("notifications not allowed: \(String(describing: error))\n".utf8))
            exit(1)
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.userInfo = ["url": url]
        content.threadIdentifier = group
        // A picture that cannot be drawn or attached still leaves the plain banner.
        if arguments.count == 5, let file = statusImage(arguments[4]) {
            if let attachment = try? UNNotificationAttachment(identifier: "status", url: file) {
                content.attachments = [attachment]
            } else {
                try? FileManager.default.removeItem(at: file)
            }
        }
        // The same identifier replaces the earlier banner of the same pull request.
        center.add(UNNotificationRequest(identifier: group, content: content, trigger: nil)) { error in
            if let error {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                exit(1)
            }
            exit(0)
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.run()
