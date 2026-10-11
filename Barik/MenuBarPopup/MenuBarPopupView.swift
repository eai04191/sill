import SwiftUI

/// How every popup appears and disappears, modeled on the system popover (NSPopover) in macOS 26: it grows out of
/// the bar while fading in and shrinks back while fading out, quickly and without bouncing or blurring. Measured on
/// screen, a popover takes about 0.17 seconds to open and 0.1 seconds to close. With Reduce Motion the popup only
/// fades, as the HIG asks in place of scaling. Liquid Glass popups materialize, the system transition for glass, and
/// fade instead of scaling (see `MenuBarPopupView.presentation`).
enum PopupMotion {
    static let showDuration = 0.18
    static let hideDuration = 0.1
    static let showAnimation = Animation.easeOut(duration: showDuration)
    static let hideAnimation = Animation.easeIn(duration: hideDuration)
    /// The scale a popup grows from and shrinks to, about where the system popover starts.
    static let initialScale: CGFloat = 0.2
}

struct MenuBarPopupView<Content: View>: View {
    /// The horizontal center of the widget the popup belongs to, in the panel's coordinates.
    let anchorX: CGFloat
    let content: Content

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    private var isBottom: Bool { configManager.config.position == .bottom }
    private var usesGlass: Bool { configManager.config.usesLiquidGlass }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The content is inserted when the popup is shown and removed when it is hidden, so both looks appear and
    /// disappear with the same transition (see `PopupMotion`).
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
        // Popups are always dark: the material popup draws a black background, and glass popups are dark like the
        // Control Center (MenuBarPopup gives their window the dark appearance, which the glass follows).
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
        .onPreferenceChange(PopupProvidesGlassModulesKey.self) { providesModules = $0 }
        // MenuBarPopup builds a new view for every popup and may post willShowWindow before this view subscribes,
        // so also show the popup when the view appears; otherwise it would stay invisible. Showing it twice animates
        // to the same value and changes nothing.
        .onAppear { appear() }
    }

    private func appear() {
        withAnimation(PopupMotion.showAnimation) { isPresented = true }
    }

    /// Grows out of the bar edge and fades, or only fades with Reduce Motion. Glass only fades while it
    /// materializes: scaling glass inside its container did not grow it but slid it at full size from below and to
    /// the side of its frame, with its content apart from the glass (seen frame by frame in a screen recording).
    private var presentation: AnyTransition {
        guard !reduceMotion, !usesGlass else { return .opacity }
        return .scale(scale: PopupMotion.initialScale, anchor: isBottom ? .bottom : .top)
            .combined(with: .opacity)
    }

    /// The popup content on its background: one glass module unless the content draws its own modules, or the
    /// black material background without Liquid Glass.
    @ViewBuilder
    private var popupBody: some View {
        if usesGlass {
            LiquidGlassContainer(enabled: true, spacing: Constants.popupModuleSpacing) {
                // The glass is inserted and removed inside its container so that it materializes in and out.
                if isPresented {
                    content
                        .popupGlass(enabled: !providesModules, in: RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
                        .containerShape(RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
                        .liquidGlassMaterializes()
                        .transition(presentation)
                }
            }
        } else if isPresented {
            // The shadow is for the material look only; see `applying(_:_:)` for why it is left out around glass.
            content
                .background(Color.black)
                .cornerRadius(40)
                .shadow(radius: 30)
                .transition(presentation)
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

