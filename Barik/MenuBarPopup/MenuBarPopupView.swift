import SwiftUI

struct MenuBarPopupView<Content: View>: View {
    /// The horizontal center of the widget the popup belongs to, in the panel's coordinates.
    let anchorX: CGFloat
    let content: Content

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    private var isBottom: Bool { configManager.config.position == .bottom }
    private var usesGlass: Bool { configManager.config.usesLiquidGlass }

    @State private var animationValue: Double = 0.01
    @State private var isHideAnimation = false
    /// Liquid Glass popups materialize instead of scaling, so their content is inserted with this flag.
    @State private var glassVisible = false
    /// Set by content that draws its own glass modules (see `popupProvidesGlassModules()`), so no outer glass is added.
    @State private var providesModules = false

    private let willShowWindow = NotificationCenter.default.publisher(
        for: .willShowWindow)
    private let willHideWindow = NotificationCenter.default.publisher(
        for: .willHideWindow)
    private let willChangeContent = NotificationCenter.default.publisher(
        for: .willChangeContent)

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
                // Liquid Glass materializes on its own; the scale, blur and shadow are for the material look only.
                // See `applying(_:_:)` for why they are left out around glass. The popup grows out of the bar.
                .applying(!usesGlass) {
                    $0.shadow(radius: 30)
                        .blur(radius: (1.0 - (0.1 + 0.9 * animationValue)) * 20)
                        .scaleEffect(
                            x: 0.2 + 0.8 * animationValue, y: animationValue, anchor: isBottom ? .bottom : .top)
                        .opacity(animationValue)
                }
                .transaction { transaction in
                    if isHideAnimation {
                        transaction.animation = .linear(duration: 0.1)
                    }
                }
                .onReceive(willShowWindow) { _ in appear() }
                .onReceive(willHideWindow) { _ in
                    // Glass popups fade out with their window (see MenuBarPopup); the scale and blur are for the
                    // material look. Animating them while a glass popup was still appearing moved it to the top left.
                    guard !usesGlass else { return }
                    isHideAnimation = true
                    withAnimation(
                        .interactiveSpring(
                            duration: Double(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            ) / 1000.0)
                    ) {
                        animationValue = 0.01
                    }
                    DispatchQueue.main.asyncAfter(
                        deadline: .now()
                            + .milliseconds(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            )
                    ) {
                        isHideAnimation = false
                    }
                }
                .onReceive(willChangeContent) { _ in
                    // Glass popups fade out with their window (see MenuBarPopup); the scale and blur are for the
                    // material look. Animating them while a glass popup was still appearing moved it to the top left.
                    guard !usesGlass else { return }
                    isHideAnimation = true
                    withAnimation(
                        .spring(
                            duration: Double(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            ) / 1000.0)
                    ) {
                        animationValue = 0.01
                    }
                    DispatchQueue.main.asyncAfter(
                        deadline: .now()
                            + .milliseconds(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            )
                    ) {
                        isHideAnimation = false
                    }
                }
        }
        // Popups are always dark: the material popup draws a black background, and glass popups are dark like the
        // Control Center (MenuBarPopup gives their window the dark appearance, which the glass follows).
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
        .onPreferenceChange(PopupProvidesGlassModulesKey.self) { providesModules = $0 }
        // MenuBarPopup builds a new view for every popup and may post willShowWindow before this view subscribes,
        // so also show the popup when the view appears; otherwise it would stay invisible. Showing it twice animates
        // to the same values and changes nothing.
        .onAppear { appear() }
    }

    /// Materializes the glass, or grows the material popup out of the bar.
    private func appear() {
        withAnimation(.smooth) { glassVisible = true }
        withAnimation(
            .smooth(
                duration: Double(
                    Constants
                        .menuBarPopupAnimationDurationInMilliseconds
                ) / 1000.0, extraBounce: 0.3)
        ) {
            animationValue = 1.0
        }
    }

    /// The popup content on its background: one glass module unless the content draws its own modules, or the
    /// black material background without Liquid Glass.
    @ViewBuilder
    private var popupBody: some View {
        if usesGlass {
            LiquidGlassContainer(enabled: true, spacing: Constants.popupModuleSpacing) {
                // The content is inserted when the popup is shown so its glass materializes; it fades out with the window.
                if glassVisible {
                    content
                        .popupGlass(enabled: !providesModules, in: RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
                        .containerShape(RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
                        .liquidGlassMaterializes()
                }
            }
        } else {
            content
                .background(Color.black)
                .cornerRadius(((1.0 - animationValue) * 1) + 40)
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
    static let willChangeContent = Notification.Name("willChangeContent")
}

