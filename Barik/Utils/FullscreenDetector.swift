import AppKit

/// Tells whether full-screen content is in front on the bar's screen, so the bar can step aside for it.
///
/// Full-screen content is the frontmost normal window of another app covering the whole screen: a native full-screen
/// window in its own Space, a browser playing video full screen, or a player that covers the screen itself. Windows
/// tiled by AeroSpace keep their gaps and do not count. The bar sits at the status window level, above the full-screen
/// Space's window, so it hid the bottom of full-screen content.
///
/// The check runs when the Space, the active app or the screens change, and every 2 seconds for content that goes
/// full screen without any of those, such as a video player in the active app. It reads only the windows' layers,
/// owners and bounds, which need no permission.
final class FullscreenDetector {
    private(set) var isFullscreen = false
    private let onChange: (Bool) -> Void
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.update()
            })
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.update()
            })
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.update() }
        update()
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        timer?.invalidate()
    }

    private func update() {
        let fullscreen = Self.frontWindowCoversBarScreen()
        guard fullscreen != isFullscreen else { return }
        isFullscreen = fullscreen
        onChange(fullscreen)
    }

    private static func frontWindowCoversBarScreen() -> Bool {
        guard let screen = NSScreen.barScreen,
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }
        let screenBounds = CGDisplayBounds(displayID)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // The list is ordered front to back; the first visible normal window of another app is the one in front.
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                (window[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                (window[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                bounds.width > 1, bounds.height > 1
            else { continue }
            return bounds == screenBounds
        }
        return false
    }
}
