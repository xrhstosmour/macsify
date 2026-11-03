import CoreGraphics

// Places the external screen centered above the built-in one, when those are the
// only two active, non-mirrored displays. Any other setup is left as it is.
// Uses `CoreGraphics` directly so no third-party display tool is needed. Positions
// are in the same points `CGDisplayBounds` reports. Exits 0 whether or not it moved
// anything, a missing or odd setup is not an error.
// Usage:
//   arrange_displays

var displayCount: UInt32 = 0
guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else { exit(0) }

var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success else { exit(0) }

let screens = displayIDs.filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
guard screens.count == 2,
      let builtIn = screens.first(where: { CGDisplayIsBuiltin($0) != 0 }),
      let external = screens.first(where: { CGDisplayIsBuiltin($0) == 0 })
else { exit(0) }

let builtInBounds = CGDisplayBounds(builtIn)
let externalBounds = CGDisplayBounds(external)

// The external screen's top-left corner, centered over the built-in screen and
// one external height above it. `CoreGraphics` origins grow downwards.
let targetX = Int32(builtInBounds.origin.x + (builtInBounds.width - externalBounds.width) / 2)
let targetY = Int32(builtInBounds.origin.y - externalBounds.height)

if Int32(externalBounds.origin.x) == targetX && Int32(externalBounds.origin.y) == targetY { exit(0) }

var configuration: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&configuration) == .success else { exit(1) }

if CGConfigureDisplayOrigin(configuration, external, targetX, targetY) != .success {
    CGCancelDisplayConfiguration(configuration)
    exit(1)
}

// Permanently, so the arrangement survives a restart like one set in System Settings.
guard CGCompleteDisplayConfiguration(configuration, .permanently) == .success else { exit(1) }
