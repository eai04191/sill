import Combine
import SwiftUI

extension NSScreen {
    /// The screen with Barik's bar and popups: the primary screen, which has the system menu bar. `NSScreen.main` is
    /// the screen with the focused window, so it would move the bar between displays as focus changes.
    static var barScreen: NSScreen? { screens.first }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var backgroundPanel: NSPanel?
    private var menuBarPanel: NSPanel?
    private var configCancellable: AnyCancellable?
    private var menuBarForcesActiveGlass = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let error = ConfigManager.shared.initError {
            showFatalConfigError(message: error)
            return
        }
        
        // Show "What's New" banner if the app version is outdated
        if !VersionChecker.isLatestVersion() {
            VersionChecker.updateVersionFile()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(
                    name: Notification.Name("ShowWhatsNewBanner"), object: nil)
            }
        }
        
        // The config file is applied asynchronously after launch, so the panels are first set up once it is, rather
        // than showing the bar with the default config and then moving it. A config file that cannot be read stops
        // Barik with the error above instead. `position` may change while running, so the panels are placed again
        // whenever the config changes.
        if ConfigManager.shared.hasLoadedConfigFile {
            setupPanels()
        }
        configCancellable = ConfigManager.shared.$config
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setupPanels() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        setupPanels()
    }

    /// Configures and displays the background and menu bar panels, and fits the popup panel to the same screen.
    /// Without a screen nothing is set up; the next screen change sets it up.
    private func setupPanels() {
        guard let screenFrame = NSScreen.barScreen?.frame else { return }
        MenuBarPopup.setup(frame: screenFrame)
        setupPanel(
            &backgroundPanel,
            frame: screenFrame,
            level: Int(CGWindowLevelForKey(.desktopWindow)),
            hostingRootView: AnyView(BackgroundView()))
        setupPanel(
            &menuBarPanel,
            frame: menuBarFrame(in: screenFrame),
            level: menuBarLevel(),
            hostingRootView: AnyView(MenuBarView()),
            fixedFrame: true)
        updateActiveGlassAppearance()
    }

    /// Only the bar has glass, and only with Liquid Glass enabled; the config may turn it on or off while running.
    private func updateActiveGlassAppearance() {
        let usesGlass = ConfigManager.shared.config.usesLiquidGlass
        if usesGlass || menuBarForcesActiveGlass {
            menuBarPanel?.setForcesActiveGlassAppearance(usesGlass)
            menuBarForcesActiveGlass = usesGlass
        }
    }

    /// At the top the bar stays behind the system menu bar, which appears over it on hover. At the bottom nothing
    /// needs to cover it, so it sits above windows like the Dock instead of being hidden by floating windows.
    private func menuBarLevel() -> Int {
        ConfigManager.shared.config.position == .bottom
            ? Int(CGWindowLevelForKey(.statusWindow))
            : Int(CGWindowLevelForKey(.backstopMenu))
    }

    /// The strip along the configured screen edge that the bar occupies.
    private func menuBarFrame(in screenFrame: CGRect) -> CGRect {
        let config = ConfigManager.shared.config
        let height = max(config.experimental.foreground.resolveHeight(), 1)
        let y = config.position == .bottom ? screenFrame.minY : screenFrame.maxY - height
        return CGRect(x: screenFrame.minX, y: y, width: screenFrame.width, height: height)
    }

    /// Sets up an NSPanel with the provided parameters.
    /// - Parameter fixedFrame: Keeps the given frame instead of letting the hosting view resize the panel
    ///   to its content, which would anchor it to the top edge.
    private func setupPanel(
        _ panel: inout NSPanel?, frame: CGRect, level: Int,
        hostingRootView: AnyView, fixedFrame: Bool = false
    ) {
        if let existingPanel = panel {
            existingPanel.level = NSWindow.Level(rawValue: level)
            existingPanel.setFrame(frame, display: true)
            return
        }

        let newPanel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false)
        newPanel.level = NSWindow.Level(rawValue: level)
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces]
        let hostingView = NSHostingView(rootView: hostingRootView)
        if fixedFrame {
            hostingView.sizingOptions = []
        }
        newPanel.contentView = hostingView
        newPanel.setFrame(frame, display: true)
        newPanel.orderFront(nil)
        panel = newPanel
    }
    
    private func showFatalConfigError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Configuration Error"
        alert.informativeText = "\(message)\n\nPlease double check ~/.barik-config.toml and try again."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        
        // Barik is an agent app and is not active at launch, so the alert would open behind other apps.
        NSApp.activate()
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}
