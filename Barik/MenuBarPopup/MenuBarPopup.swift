import SwiftUI

private var panel: NSPanel?

class HidingPanel: NSPanel, NSWindowDelegate {
    var hideTimer: Timer?

    override var canBecomeKey: Bool {
        return true
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect, styleMask: style, backing: bufferingType,
            defer: flag)
        self.delegate = self
    }

    func windowDidResignKey(_ notification: Notification) {
        NotificationCenter.default.post(name: .willHideWindow, object: nil)
        MenuBarPopup.fadeOutIfGlass(self)
        hideTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(
                Constants.menuBarPopupAnimationDurationInMilliseconds) / 1000.0,
            repeats: false
        ) { [weak self] _ in
            self?.orderOut(nil)
        }
    }
}

class MenuBarPopup {
    static var lastContentIdentifier: String? = nil

    /// The panel edge next to the bar, where the popup is anchored before MenuBarPopupView shifts it into the screen.
    private static func edgeY(of panel: NSPanel) -> CGFloat {
        ConfigManager.shared.config.position == .bottom ? panel.frame.height : 0
    }

    static func show<Content: View>(
        rect: CGRect, id: String, @ViewBuilder content: @escaping () -> Content
    ) {
        guard let panel = panel else { return }

        if panel.isKeyWindow, lastContentIdentifier == id {
            NotificationCenter.default.post(name: .willHideWindow, object: nil)
            fadeOutIfGlass(panel)
            let duration =
                Double(Constants.menuBarPopupAnimationDurationInMilliseconds)
                / 1000.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                panel.orderOut(nil)
                lastContentIdentifier = nil
            }
            return
        }

        applyAppearance(to: panel)

        let isContentChange =
            panel.isKeyWindow
            && (lastContentIdentifier != nil && lastContentIdentifier != id)
        lastContentIdentifier = id

        if let hidingPanel = panel as? HidingPanel {
            hidingPanel.hideTimer?.invalidate()
            hidingPanel.hideTimer = nil
        }

        if panel.isKeyWindow {
            NotificationCenter.default.post(
                name: .willChangeContent, object: nil)
            fadeOutIfGlass(panel)
            let baseDuration =
                Double(Constants.menuBarPopupAnimationDurationInMilliseconds)
                / 1000.0
            let duration = isContentChange ? baseDuration / 2 : baseDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                panel.contentView = NSHostingView(
                    rootView:
                        ZStack {
                            MenuBarPopupView {
                                content()
                            }
                            .position(x: rect.midX, y: edgeY(of: panel))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(UUID())
                )
                panel.alphaValue = 1
                panel.makeKeyAndOrderFront(nil)
                clearInitialFocus(of: panel)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .willShowWindow, object: nil)
                }
            }
        } else {
            panel.contentView = NSHostingView(
                rootView:
                    ZStack {
                        MenuBarPopupView {
                            content()
                        }
                        .position(x: rect.midX, y: edgeY(of: panel))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            panel.alphaValue = 1
            panel.makeKeyAndOrderFront(nil)
            clearInitialFocus(of: panel)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .willShowWindow, object: nil)
            }
        }
    }

    /// Glass popups are dark in either system appearance, like the Control Center modules in macOS 26 and later.
    /// The window appearance, not the SwiftUI color scheme, decides whether Liquid Glass is drawn light or dark.
    /// The material popup keeps the system appearance and draws its own black background.
    /// The glass also keeps its active look while the popup fades out after it stops being key.
    private static func applyAppearance(to panel: NSPanel) {
        let usesGlass = ConfigManager.shared.config.usesLiquidGlass
        panel.appearance = usesGlass ? NSAppearance(named: .darkAqua) : nil
        if usesGlass || panelForcesActiveGlass {
            panel.setForcesActiveGlassAppearance(usesGlass)
            panelForcesActiveGlass = usesGlass
        }
    }
    private static var panelForcesActiveGlass = false

    /// Fades a glass popup out with its window. Liquid Glass ignores the opacity of the SwiftUI views around it, so
    /// fading the view would leave the glass in place until the window is ordered out.
    static func fadeOutIfGlass(_ panel: NSPanel) {
        guard ConfigManager.shared.config.usesLiquidGlass else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }
    }

    /// The panel becomes key to receive clicks, and AppKit then focuses its first control, drawing a focus ring
    /// before any keyboard use. Clear that initial focus once the content is laid out; pressing Tab still moves
    /// focus with the standard ring for keyboard navigation.
    private static func clearInitialFocus(of panel: NSPanel) {
        DispatchQueue.main.async {
            panel.makeFirstResponder(nil)
        }
    }

    static func setup() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let panelFrame = NSRect(
            x: 0,
            y: 0,
            width: screen.size.width,
            height: screen.size.height
        )

        let newPanel = HidingPanel(
            contentRect: panelFrame,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newPanel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces]

        panel = newPanel
    }
}
