import CoreGraphics
import Foundation
// Usage: keys text <string> | keys code <key code>  Sends synthesized key presses.
let mode = CommandLine.arguments[1], value = CommandLine.arguments[2]
func post(_ code: CGKeyCode, _ text: String? = nil) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        if let text { let u = Array(text.utf16); e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u) }
        e.post(tap: .cghidEventTap); usleep(20_000)
    }
}
if mode == "text" { for ch in value { post(0, String(ch)) } } else { post(CGKeyCode(Int(value)!)) }
