import SwiftUI

/// How every popup appears and disappears, timed like the system popover (NSPopover) in macOS 26: quickly and without
/// bouncing or blurring. Measured on screen, a popover takes about 0.17 seconds to open and 0.1 seconds to close. The
/// popup's glass materializes, the system transition for glass, while the popup fades instead of scaling (see
/// `MenuBarPopupView.presentation`), which is also what the HIG asks for with Reduce Motion.
enum PopupMotion {
    static let showDuration = 0.18
    static let hideDuration = 0.1
    static let showAnimation = Animation.easeOut(duration: showDuration)
    static let hideAnimation = Animation.easeIn(duration: hideDuration)
}

struct MenuBarPopupView<Content: View>: View {
    /// The horizontal center of the widget the popup belongs to, in the panel's coordinates.
    let anchorX: CGFloat
    let content: Content

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    private var isBottom: Bool { configManager.config.position == .bottom }

    /// The content is inserted when the popup is shown and removed when it is hidden, so it appears and disappears
    /// with a transition (see `PopupMotion`).
    @State private var isPresented = false
    /// Set by content that draws its own glass modules (see `popupProvidesGlassModules()`), so no outer glass is added.
    @State private var providesModules = false

    private let willShowWindow = NotificationCenter.default.publisher(
        for: .willShowWindow)
    private let willHideWindow = NotificationCenter.default.publisher(
        for: .willHideWindow)

    init(anchorX: CGFloat, @ViewBuilder content: () -> Content) {
        self.anchorX = anchorX
        self.content = content()
    }

    var body: some View {
        // The layout places the popup in the same pass that measures it, so it is never drawn before its size is
        // known, as it was when a measured frame shifted it into place on the next update.
        PopupPlacement(anchorX: anchorX, isBottom: isBottom) {
            popupBody
                .padding(isBottom ? .bottom : .top, foregroundHeight + 5)
                .onReceive(willShowWindow) { _ in appear() }
                .onReceive(willHideWindow) { _ in
                    withAnimation(PopupMotion.hideAnimation) { isPresented = false }
                }
        }
        .onPreferenceChange(PopupProvidesGlassModulesKey.self) { providesModules = $0 }
        // MenuBarPopup builds a new view for every popup and may post willShowWindow before this view subscribes,
        // so also show the popup when the view appears; otherwise it would stay invisible. Showing it twice animates
        // to the same value and changes nothing.
        .onAppear { appear() }
    }

    private func appear() {
        withAnimation(PopupMotion.showAnimation) { isPresented = true }
    }

    /// Glass only fades while it materializes: scaling glass inside its container did not grow it but slid it at full
    /// size from below and to the side of its frame, with its content apart from the glass (seen frame by frame in a
    /// screen recording).
    private var presentation: AnyTransition { .opacity }

    /// The popup content on one glass module, unless the content draws its own modules.
    private var popupBody: some View {
        LiquidGlassContainer(spacing: Constants.popupModuleSpacing) {
            // The glass is inserted and removed inside its container so that it materializes in and out.
            if isPresented {
                content
                    .popupGlass(enabled: !providesModules, in: RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
                    .containerShape(RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
                    .liquidGlassMaterializes()
                    .transition(presentation)
            }
        }
    }
}

/// Places the popup next to the bar under its widget: its bar-side edge on the panel edge next to the bar (the popup's
/// padding keeps it clear of the bar) and centered on the widget, kept 20 points inside the panel's sides.
private struct PopupPlacement: Layout {
    let anchorX: CGFloat
    let isBottom: Bool

    private let margin: CGFloat = 20

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(bounds.size))
            var x = bounds.minX + anchorX - size.width / 2
            if x + size.width + margin > bounds.maxX {
                x = bounds.maxX - margin - size.width
            } else if x - margin < bounds.minX {
                x = bounds.minX + margin
            }
            let y = isBottom ? bounds.maxY - size.height : bounds.minY
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}

extension Notification.Name {
    static let willShowWindow = Notification.Name("willShowWindow")
    static let willHideWindow = Notification.Name("willHideWindow")
}

