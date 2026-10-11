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

    /// Whether a popup is shown or about to be shown, as opposed to hidden or disappearing.
    private static var isShown = false
    /// The delayed step of the latest show or hide: showing the new content once the old popup has disappeared, or
    /// ordering the panel out once the popup has disappeared. Each show or hide cancels the previous step, so a step
    /// scheduled for an earlier popup never hides or shows a later one.
    private static var pendingStep: DispatchWorkItem?

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

        // Like the system popovers, one popup is closed before the next one opens, with the same transitions as
        // closing and opening each (see PopupMotion).
        if isContentChange {
            NotificationCenter.default.post(name: .willHideWindow, object: nil)
            schedule(after: PopupMotion.hideDuration) {
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
        schedule(after: PopupMotion.hideDuration) {
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
        panel.makeKeyAndOrderFront(nil)
        clearInitialFocus(of: panel)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .willShowWindow, object: nil)
            announceToAssistiveTechnologies(panel)
        }
    }

    /// Barik stays in the background while its popup is key, so tell VoiceOver that the popup opened and point it at
    /// the popup's content; Escape closes the popup (see HidingPanel).
    private static func announceToAssistiveTechnologies(_ panel: NSPanel) {
        guard isShown, let contentView = panel.contentView else { return }
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [
                .announcement: "Popup opened. Press Escape to close.",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        NSAccessibility.post(
            element: contentView, notification: .layoutChanged, userInfo: [.uiElements: [contentView]])
    }

    /// Popups follow the `theme` setting: the system appearance by default, as the HIG asks apps to follow the
    /// appearance people choose, or always light or dark. The window appearance, not the SwiftUI color scheme,
    /// decides whether Liquid Glass is drawn light or dark. The glass also keeps its active look while the popup
    /// disappears after it stops being key.
    private static func applyAppearance(to panel: NSPanel) {
        switch ConfigManager.shared.config.rootToml.theme {
        case "dark": panel.appearance = NSAppearance(named: .darkAqua)
        case "light": panel.appearance = NSAppearance(named: .aqua)
        default: panel.appearance = nil
        }
        panel.setForcesActiveGlassAppearance(true)
    }

    /// The panel becomes key to receive clicks, and AppKit then focuses its first control, drawing a focus ring
    /// before any keyboard use. Clear that initial focus once the content is laid out; pressing Tab still moves
    /// focus with the standard ring for keyboard navigation.
    private static func clearInitialFocus(of panel: NSPanel) {
        DispatchQueue.main.async {
            panel.makeFirstResponder(nil)
        }
    }

    /// Creates the popup panel, or moves it, to cover `frame`: the whole screen with the bar, so a popup sits right
    /// next to the bar on whichever edge it is, and is kept inside the screen's sides.
    static func setup(frame: CGRect) {
        if let panel {
            panel.setFrame(frame, display: true)
            // Also called when the config is reloaded, so an open popup takes on a changed theme.
            applyAppearance(to: panel)
            return
        }

        let newPanel = HidingPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newPanel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces]
        newPanel.setFrame(frame, display: false)

        panel = newPanel
    }
}
