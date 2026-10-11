import CoreGraphics
// Usage: windows <pid>  Prints the windows of the process: window number, layer, bounds (points, origin at the top left)
// and whether it is on screen. Pass a window number to `screencapture -l` to capture that window alone.
let pid = Int(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for window in windows where (window[kCGWindowOwnerPID as String] as? Int) == pid {
    let bounds = window[kCGWindowBounds as String] as! [String: Any]
    let onScreen = (window[kCGWindowIsOnscreen as String] as? Bool) ?? false
    print(window[kCGWindowNumber as String]!, window[kCGWindowLayer as String]!, bounds["X"]!, bounds["Y"]!, bounds["Width"]!, bounds["Height"]!, onScreen ? "on" : "off")
}
