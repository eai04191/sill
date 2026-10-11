import SwiftUI

@main
struct BarikApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // A SwiftUI app needs a scene, but Barik has no settings window: its settings are the config file. Remove the
        // Settings menu item so Command-Comma does not open an empty window.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}
