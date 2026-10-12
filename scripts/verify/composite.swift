import AppKit
import ScreenCaptureKit
// Usage: composite <png> <window number>...  Captures the windows together, composited as the window server shows them
// on the display, into <png>. The first window's bounds give the size; pass the window to show first.
let arguments = CommandLine.arguments
guard arguments.count >= 3 else { print("Usage: composite <png> <window number>..."); exit(1) }
let url = URL(fileURLWithPath: arguments[1])
let numbers = arguments.dropFirst(2).map { CGWindowID($0)! }

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let windows = numbers.map { number in
            guard let window = content.windows.first(where: { $0.windowID == number }) else {
                print("No window \(number)"); exit(1)
            }
            return window
        }
        let frame = windows[0].frame
        guard let display = content.displays.first(where: { $0.frame.contains(frame.origin) }) else {
            print("No display shows window \(numbers[0])"); exit(1)
        }
        let filter = SCContentFilter(display: display, including: windows)
        let configuration = SCStreamConfiguration()
        let scale = filter.pointPixelScale
        configuration.sourceRect = frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        configuration.width = Int(frame.width * CGFloat(scale))
        configuration.height = Int(frame.height * CGFloat(scale))
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
        exit(0)
    } catch {
        print(error)
        exit(1)
    }
}
RunLoop.main.run()
