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
    /// The content draws its own glass modules, so no outer glass is added. It is given when the popup opens rather
    /// than reported by the content through a preference: a preference read into state while the content was inserted
    /// kept the modules' glass from materializing, so they appeared at once (see `MenuBarPopup.show`).
    private let providesModules: Bool

    private let willShowWindow = NotificationCenter.default.publisher(
        for: .willShowWindow)
    private let willHideWindow = NotificationCenter.default.publisher(
        for: .willHideWindow)

    init(anchorX: CGFloat, providesModules: Bool, @ViewBuilder content: () -> Content) {
        self.anchorX = anchorX
        self.providesModules = providesModules
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

    /// The popup sits between the bar and the other edge of the screen, with room left for its margins.
    private var maxHeight: CGFloat {
        let screenHeight = NSScreen.barScreen?.visibleFrame.height ?? 800
        return max(screenHeight - foregroundHeight - 80, 100)
    }

    /// The popup content on one glass module, unless the content draws its own modules.
    private var popupBody: some View {
        LiquidGlassContainer(spacing: Constants.popupModuleSpacing) {
            // The glass is inserted and removed inside its container so that it materializes in and out.
            if isPresented {
                // Every popup scrolls only when it would be taller than the screen, such as the calendar on a day with
                // many events. The content is built once, in a scroll view as tall as the content up to the limit. A
                // ViewThatFits with the content and a scrolling copy of it built the content several times and swapped
                // the copies as their sizes changed, which reset their state and restarted their tasks; with the
                // window switcher the swapping did not end, and Barik hung and crashed.
                HeightLimit(maxHeight: maxHeight) {
                    ScrollView { content }
                        .scrollIndicators(.automatic)
                        .scrollBounceBehavior(.basedOnSize)
                }
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

/// Makes a scroll view as tall as its content, up to `maxHeight` and the height offered. A scroll view asked for its
/// size without a height reports its content's height; offered a height, it takes all of it, and a
/// `frame(maxHeight:)` likewise grows to the height it is offered, which made the popup as tall as the screen.
private struct HeightLimit: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let content = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: content.width, height: min(content.height, proposal.height ?? maxHeight, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
