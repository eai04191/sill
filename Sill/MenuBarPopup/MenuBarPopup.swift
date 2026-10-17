import SwiftUI
import os

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

/// One popup in the panel: its own hosting view, so the popup it replaces can disappear while it appears.
private struct PresentedPopup {
    let id: String
    /// Tells this popup's view, and not the others in the panel, to appear or disappear (see `MenuBarPopupView`).
    let presentationID: UUID
    let view: PopupHostingView
}

/// A popup's hosting view, which stops taking clicks once its popup starts to disappear, so a click during the
/// transition reaches the popup that replaces it.
private final class PopupHostingView: NSHostingView<AnyView> {
    var isDisappearing = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        isDisappearing ? nil : super.hitTest(point)
    }
}

class MenuBarPopup {
    /// The popup shown or about to be shown, as opposed to hidden or disappearing.
    private static var current: PresentedPopup?

    /// - Parameter providesGlassModules: The content draws its own glass modules, so the popup adds no glass behind
    ///   them (glass on glass, which the HIG asks to avoid).
    /// - Parameter focusesContent: The content puts keyboard focus on one of its controls itself, such as a search
    ///   field, so the popup does not clear the initial focus (see `clearInitialFocus`), which could otherwise run
    ///   after the content focused its control and take the focus away again.
    static func show<Content: View>(
        rect: CGRect, id: String, providesGlassModules: Bool = false, focusesContent: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        guard let panel = panel else { return }

        if current?.id == id {
            hide()
            return
        }
        Logger.popup.notice("Showing popup \(id, privacy: .public)")

        applyAppearance(to: panel)

        // Switching to another widget's popup disappears the open popup while the new one appears, each with its own
        // transition (see PopupMotion), rather than waiting for the open popup to be gone first.
        if let previous = current {
            dismiss(previous, from: panel)
        }
        current = present(
            id: id, in: panel, rect: rect, providesGlassModules: providesGlassModules, focusesContent: focusesContent,
            content: content)
    }

    /// Hides the popup: closing it by clicking its widget again or pressing Escape, or the panel losing key status.
    /// Ordering the panel out also makes it lose key status, which then finds the popup already hiding.
    static func hide() {
        guard let popup = current, let panel = panel else { return }
        Logger.popup.notice("Hiding popup \(popup.id, privacy: .public)")
        current = nil
        dismiss(popup, from: panel)
    }

    /// Lets the popup disappear, then removes its view, and orders the panel out once no popup is left in it. A popup
    /// shown while this one disappears keeps the panel ordered in.
    private static func dismiss(_ popup: PresentedPopup, from panel: NSPanel) {
        popup.view.isDisappearing = true
        NotificationCenter.default.post(name: .willHideWindow, object: popup.presentationID)
        DispatchQueue.main.asyncAfter(deadline: .now() + PopupMotion.hideDuration) {
            popup.view.removeFromSuperview()
            if current == nil, panel.contentView?.subviews.isEmpty ?? true {
                panel.orderOut(nil)
            }
        }
    }

    private static func present<Content: View>(
        id: String, in panel: NSPanel, rect: CGRect, providesGlassModules: Bool, focusesContent: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> PresentedPopup {
        let presentationID = UUID()
        let view = PopupHostingView(
            rootView: AnyView(
                MenuBarPopupView(
                    presentationID: presentationID, anchorX: rect.midX, providesModules: providesGlassModules
                ) {
                    content()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)))
        if let container = panel.contentView {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        if HiddenInstance.isEnabled {
            panel.orderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        if !focusesContent {
            clearInitialFocus(of: panel)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .willShowWindow, object: presentationID)
            // A hidden instance's popup is not on the display, so VoiceOver should not interrupt the maintainer for it.
            if !HiddenInstance.isEnabled {
                announceToAssistiveTechnologies(view)
            }
        }
        return PresentedPopup(id: id, presentationID: presentationID, view: view)
    }

    /// Sill stays in the background while its popup is key, so tell VoiceOver that the popup opened and point it at
    /// the popup's content; Escape closes the popup (see HidingPanel).
    private static func announceToAssistiveTechnologies(_ contentView: NSView) {
        guard current?.view === contentView else { return }
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [
                .announcement: String(localized: "Popup opened. Press Escape to close."),
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
            rawValue: HiddenInstance.isEnabled ? HiddenInstance.windowLevel : Int(CGWindowLevelForKey(.floatingWindow)))
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces]
        newPanel.setFrame(frame, display: false)
        // Holds a hosting view for each popup in the panel (see `present`).
        newPanel.contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))

        panel = newPanel
    }
}
