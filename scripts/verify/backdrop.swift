import AppKit
// Usage: backdrop <seconds>  Covers the lower part of the screen with dense text, behind the bar, for checking glass.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!.frame
let rect = NSRect(x: 0, y: 0, width: screen.width, height: 700)
let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
window.level = .normal
window.backgroundColor = .white
let text = NSTextView(frame: NSRect(origin: .zero, size: rect.size))
text.backgroundColor = .white
text.textColor = .black
text.font = .systemFont(ofSize: 18, weight: .bold)
text.string = String(repeating: "THE QUICK BROWN FOX 文字が透けるかの確認 0123456789 ", count: 400)
window.contentView = text
window.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + Double(CommandLine.arguments[1])!) { exit(0) }
app.run()
