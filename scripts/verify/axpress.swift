import AppKit
import ApplicationServices
// Usage: axpress list | axpress press <label>
// Lists Sill's buttons, or presses the one whose description or title is <label>, through the accessibility API
// without moving the pointer.
guard AXIsProcessTrusted() else { print("not trusted for accessibility"); exit(1) }
guard let sill = NSRunningApplication.runningApplications(withBundleIdentifier: "net.mizle.sill").first else {
    print("Sill is not running"); exit(1)
}
let root = AXUIElementCreateApplication(sill.processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func walk(_ element: AXUIElement, _ visit: (AXUIElement) -> Void) {
    visit(element)
    for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(child, visit) }
}

let mode = CommandLine.arguments[1]
var pressed = false
walk(root) { element in
    guard (attribute(element, kAXRoleAttribute) as? String) == kAXButtonRole else { return }
    let label = (attribute(element, kAXDescriptionAttribute) as? String) ?? (attribute(element, kAXTitleAttribute) as? String) ?? ""
    if mode == "list" {
        print(label, "|", (attribute(element, kAXValueAttribute) as? String) ?? "")
    } else if !pressed, label == CommandLine.arguments[2] {
        print("press", label, AXUIElementPerformAction(element, kAXPressAction as CFString).rawValue)
        pressed = true
    }
}
if mode == "press", !pressed { print("not found"); exit(1) }
