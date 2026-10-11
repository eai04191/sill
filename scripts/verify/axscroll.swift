import AppKit
import ApplicationServices
// Usage: axscroll <0...1>  Scrolls each scroll area in Sill, such as an open popup's, to the position (0 is the top, 1
// the bottom) by setting its vertical scroll bar through the accessibility API, without moving the pointer.
guard AXIsProcessTrusted() else { print("not trusted for accessibility"); exit(1) }
// With SILL_PID set, it acts on that Sill, such as a hidden instance from hidden-sill.sh, instead of the first one running.
let sillPID = ProcessInfo.processInfo.environment["SILL_PID"].map { pid_t($0)! }
let running: NSRunningApplication? =
    if let sillPID { NSRunningApplication(processIdentifier: sillPID) }
    else { NSRunningApplication.runningApplications(withBundleIdentifier: "net.mizle.sill").first }
guard let sill = running else {
    print("Sill is not running"); exit(1)
}
let position = Double(CommandLine.arguments[1])!
let root = AXUIElementCreateApplication(sill.processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func walk(_ element: AXUIElement, _ visit: (AXUIElement) -> Void) {
    visit(element)
    for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(child, visit) }
}

var found = 0
walk(root) { element in
    guard (attribute(element, kAXRoleAttribute) as? String) == kAXScrollAreaRole else { return }
    found += 1
    guard let bar = attribute(element, kAXVerticalScrollBarAttribute) else {
        print("a scroll area without a vertical scroll bar (its content fits)"); return
    }
    let scrollBar = bar as! AXUIElement
    let before = attribute(scrollBar, kAXValueAttribute) ?? "nil" as NSString
    let result = AXUIElementSetAttributeValue(scrollBar, kAXValueAttribute as CFString, NSNumber(value: position))
    print("scrolled from", before, "to", attribute(scrollBar, kAXValueAttribute) ?? "nil" as NSString, "result", result.rawValue)
}
print("scroll areas:", found)
