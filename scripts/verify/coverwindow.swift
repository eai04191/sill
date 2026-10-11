import AppKit
// Usage: coverwindow  Covers the whole screen with a borderless window for 8 seconds, as apps that go full screen
// without native full screen do. Click it to bring it to the front.
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSScreen.main!.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .systemBlue
        window.level = .normal
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { exit(0) }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate
app.run()
