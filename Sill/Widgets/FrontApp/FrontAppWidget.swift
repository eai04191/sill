import AppKit
import SwiftUI

/// Follows the frontmost application through NSWorkspace activation notifications.
final class FrontAppManager: ObservableObject {
    static let shared = FrontAppManager()

    @Published private(set) var app: NSRunningApplication?
    private var observer: NSObjectProtocol?

    private init() {
        app = Self.shown(NSWorkspace.shared.frontmostApplication) ?? Self.frontmostWindowOwner()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let app = Self.shown(activated) {
                self?.app = app
            }
        }
    }

    /// When Sill itself is frontmost at launch, use the owner of the frontmost normal window instead.
    private static func frontmostWindowOwner() -> NSRunningApplication? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular
            else { continue }
            return app
        }
        return nil
    }

    /// The app to show, or nil to keep showing the app the user was working in: only regular apps, which have a
    /// menu bar of their own, as the macOS menu bar shows. Sill becomes active when it launches or a popup takes
    /// focus, and macOS makes loginwindow, a background process, active when the active app quits until another app
    /// is activated.
    private static func shown(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app, app.activationPolicy == .regular,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return app
    }
}

/// Shows the frontmost application's icon and name, like the bold app menu of the macOS menu bar. Clicking it opens the
/// window switcher (see `WindowSwitcherPopup`).
///
/// Config (`[widgets.default.frontapp]`):
/// - `show-icon`: show the application icon (default `true`).
struct FrontAppWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var frontAppManager = FrontAppManager.shared
    var showIcon: Bool { configProvider.config["show-icon"]?.boolValue ?? true }

    @State private var rect: CGRect = .zero

    var body: some View {
        if let app = frontAppManager.app, let name = app.localizedName {
            HStack(spacing: 6) {
                if showIcon, let icon = app.icon {
                    // The app name next to it is read instead.
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                Text(name)
                    .font(.barText)
                    .lineLimit(1)
            }
            .experimentalConfiguration()
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.001))
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rect = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                            rect = newFrame
                        }
                }
            )
            .barWidgetButton(label: "Windows", value: name) {
                MenuBarPopup.show(rect: rect, id: "windowswitcher", focusesContent: true) {
                    WindowSwitcherPopup()
                }
            }
            // Outside the button, so the button's glass, which is the chip, follows the new name's width too.
            .animation(.smooth(duration: 0.15), value: name)
        }
    }
}
