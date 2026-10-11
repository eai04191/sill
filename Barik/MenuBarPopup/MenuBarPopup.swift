import SwiftUI

private var panel: NSPanel?

class HidingPanel: NSPanel, NSWindowDelegate {
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
        MenuBarPopup.hide()
    }

    /// Escape closes the popup, as it does a menu or popover. It reaches here whether the panel or a control in the
    /// popup has keyboard focus, unless the focused control handles Escape itself.
    override func cancelOperation(_ sender: Any?) {
        MenuBarPopup.hide()
    }
}

class MenuBarPopup {
    static var lastContentIdentifier: String? = nil

    /// Whether a popup is shown or about to be shown, as opposed to hidden or fading out.
    private static var isShown = false
    /// The delayed step of the latest show or hide: showing the new content once the old content has faded, or
    /// ordering the panel out once the popup has faded. Each show or hide cancels the previous step, so a step
    /// scheduled for an earlier popup never hides or shows a later one.
    private static var pendingStep: DispatchWorkItem?

    private static var animationDuration: Double {
        Double(Constants.menuBarPopupAnimationDurationInMilliseconds) / 1000.0
    }

    static func show<Content: View>(
        rect: CGRect, id: String, @ViewBuilder content: @escaping () -> Content
    ) {
        guard let panel = panel else { return }

        if isShown, lastContentIdentifier == id {
            hide()
            return
        }

        applyAppearance(to: panel)

        let isContentChange = isShown
        isShown = true
        lastContentIdentifier = id
        pendingStep?.cancel()
        pendingStep = nil

        if isContentChange {
            NotificationCenter.default.post(
                name: .willChangeContent, object: nil)
            fadeOutIfGlass(panel)
            schedule(after: animationDuration / 2) {
                present(in: panel, rect: rect, content: content)
            }
        } else {
            present(in: panel, rect: rect, content: content)
        }
    }

    /// Hides the popup: closing it by clicking its widget again or pressing Escape, or the panel losing key status.
    /// Ordering the panel out also makes it lose key status, which then finds the popup already hiding.
    static func hide() {
        guard isShown, let panel = panel else { return }
        isShown = false
        NotificationCenter.default.post(name: .willHideWindow, object: nil)
        fadeOutIfGlass(panel)
        schedule(after: animationDuration) {
            panel.orderOut(nil)
            lastContentIdentifier = nil
        }
    }

    private static func schedule(after delay: Double, _ step: @escaping () -> Void) {
        pendingStep?.cancel()
        let workItem = DispatchWorkItem(block: step)
        pendingStep = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private static func present<Content: View>(
        in panel: NSPanel, rect: CGRect, @ViewBuilder content: @escaping () -> Content
    ) {
        panel.contentView = NSHostingView(
            rootView:
                MenuBarPopupView(anchorX: rect.midX) {
                    content()
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
