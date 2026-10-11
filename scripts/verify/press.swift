import CoreGraphics
import Foundation
// Usage: press x y  Moves the pointer onto the point from the left, then presses for 0.3 seconds and releases
// (points, origin at the top left).
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
for i in 0...20 {
    let p = CGPoint(x: x - 60 + Double(i) * 3, y: y)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(16_000)
}
usleep(400_000)
let p = CGPoint(x: x, y: y)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
usleep(300_000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
