import AppKit
import SwiftUI

/// Follows the frontmost application through NSWorkspace activation notifications.
final class FrontAppManager: ObservableObject {
    static let shared = FrontAppManager()

    @Published private(set) var app: NSRunningApplication?
    private var observer: NSObjectProtocol?

    private init() {
        app = Self.ignoringSelf(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let app = Self.ignoringSelf(activated) {
                self?.app = app
            }
        }
    }

    /// Barik becomes active when it launches or a popup takes focus; keep showing the app the user was working in.
    private static func ignoringSelf(_ app: NSRunningApplication?) -> NSRunningApplication? {
        app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app
    }
}

/// Shows the frontmost application's icon and name, like the bold app menu of the macOS menu bar.
///
/// Config (`[widgets.default.frontapp]`):
/// - `show-icon`: show the application icon (default `true`).
struct FrontAppWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var frontAppManager = FrontAppManager.shared
    var showIcon: Bool { configProvider.config["show-icon"]?.boolValue ?? true }

    var body: some View {
        if let app = frontAppManager.app, let name = app.localizedName {
            HStack(spacing: 6) {
                if showIcon, let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.foregroundOutside)
            .experimentalConfiguration(cornerRadius: 15)
            .frame(maxHeight: .infinity)
            .animation(.smooth(duration: 0.15), value: name)
        }
    }
}
