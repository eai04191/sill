import AppKit
// Usage: clickthrough x y
// Puts a window at the bottom of the screen that reaches behind the bar, clicks the point (points, origin at the
// top left), and prints whether the click reached that window rather than the bar.
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
final class ProbeView: NSView {
    var received = false
    override func mouseDown(with event: NSEvent) { received = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!.frame
let window = NSWindow(contentRect: NSRect(x: x - 50, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
window.level = .normal
window.backgroundColor = .systemRed
let probe = ProbeView()
window.contentView = probe
window.orderFrontRegardless()
_ = screen
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    let p = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    print(probe.received ? "reached the window behind" : "did not reach the window behind")
    exit(0)
}
app.run()
