import CoreGraphics
import AppKit
// Usage: winlist  Prints the windows on screen front to back: layer, owner, bounds and alpha (not their titles).
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list.prefix(14) {
    let b = w[kCGWindowBounds as String] as! [String: Double]
    print(w[kCGWindowLayer as String] ?? "", w[kCGWindowOwnerName as String] ?? "", Int(b["X"]!), Int(b["Y"]!), Int(b["Width"]!), Int(b["Height"]!), w[kCGWindowAlpha as String] ?? "")
}
print("visibleFrame", NSScreen.main!.visibleFrame, "frame", NSScreen.main!.frame)
