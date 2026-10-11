import CoreGraphics
import Foundation
// Usage: scroll x y lines  Puts the pointer on the point and scrolls by lines, ten times (negative scrolls down).
let p = CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
usleep(100_000)
for _ in 0..<10 {
    CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(CommandLine.arguments[3])!, wheel2: 0, wheel3: 0)!.post(tap: .cghidEventTap)
    usleep(30_000)
}
