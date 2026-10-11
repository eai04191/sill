import CoreGraphics
import Foundation
// Usage: under x y  Prints the windows on screen that contain the point, front to back (points, origin at the top left).
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
    let b = w[kCGWindowBounds as String] as! [String: Double]
    let r = CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
    if r.contains(CGPoint(x: x, y: y)) {
        print(w[kCGWindowOwnerName as String] ?? "", w[kCGWindowNumber as String] ?? "", w[kCGWindowLayer as String] ?? "", r)
    }
}
