import SwiftUI

struct MenuBarPopupView<Content: View>: View {
    let content: Content
    let isPreview: Bool

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    private var isBottom: Bool { configManager.config.position == .bottom }
    private var usesGlass: Bool { configManager.config.usesLiquidGlass }

    @State private var contentHeight: CGFloat = 0
    @State private var viewFrame: CGRect = .zero
    @State private var animationValue: Double = 0.01
    private var animated: Bool { isShowAnimation || isHideAnimation }
    @State private var isShowAnimation = false
    @State private var isHideAnimation = false
    /// Liquid Glass popups materialize instead of scaling, so their content is shown and hidden with this flag.
    @State private var glassVisible = false
    /// Set by content that draws its own glass modules (see `popupProvidesGlassModules()`), so no outer glass is added.
    @State private var providesModules = false

    private let willShowWindow = NotificationCenter.default.publisher(
        for: .willShowWindow)
    private let willHideWindow = NotificationCenter.default.publisher(
        for: .willHideWindow)
    private let willChangeContent = NotificationCenter.default.publisher(
        for: .willChangeContent)

    init(isPreview: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.isPreview = isPreview
        if isPreview {
            _animationValue = State(initialValue: 1.0)
            _glassVisible = State(initialValue: true)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            popupBody
                .padding(isBottom ? .bottom : .top, foregroundHeight + 5)
                .offset(x: computedOffset, y: computedYOffset)
                // Liquid Glass materializes on its own; the scale, blur and shadow are for the material look only.
                // See `applying(_:_:)` for why they are left out around glass.
                .applying(!usesGlass) {
                    $0.shadow(radius: 30)
                        .blur(radius: (1.0 - (0.1 + 0.9 * animationValue)) * 20)
                        .scaleEffect(x: 0.2 + 0.8 * animationValue, y: animationValue)
                        .opacity(animationValue)
                }
                .transaction { transaction in
                    if isHideAnimation {
                        transaction.animation = .linear(duration: 0.1)
                    }
                }
                .onReceive(willShowWindow) { _ in
                    withAnimation(.smooth) { glassVisible = true }
                    isShowAnimation = true
                    withAnimation(
                        .smooth(
                            duration: Double(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            ) / 1000.0, extraBounce: 0.3)
                    ) {
                        animationValue = 1.0
                    }
                    DispatchQueue.main.asyncAfter(
                        deadline: .now()
                            + .milliseconds(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            )
                    ) {
                        isShowAnimation = false
                    }
                }
                .onReceive(willHideWindow) { _ in
                    withAnimation(.smooth) { glassVisible = false }
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
                    withAnimation(.smooth) { glassVisible = false }
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
                .animation(
                    .smooth(duration: 0.3), value: animated ? 0 : computedOffset
                )
                .animation(
                    .smooth(duration: 0.3),
                    value: animated ? 0 : computedYOffset
                )
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        DispatchQueue.main.async {
                            viewFrame = geometry.frame(in: .global)
                            contentHeight = geometry.size.height
                        }
                    }
                    .onChange(of: geometry.size) { _, __ in
                        viewFrame = geometry.frame(in: .global)
                        contentHeight = geometry.size.height
                    }
            }
        )
        // The material popup is always dark. Glass follows the system appearance like other system popovers and
        // the Control Center, and its content uses semantic colors that Liquid Glass keeps legible.
        .foregroundStyle(usesGlass ? Color.primary : Color.white)
        .applying(!usesGlass) { $0.preferredColorScheme(.dark) }
        .onPreferenceChange(PopupProvidesGlassModulesKey.self) { providesModules = $0 }
        // MenuBarPopup builds a new view for every popup and may post willShowWindow before this view subscribes,
        // so also materialize the glass when the view appears.
        .onAppear {
            guard usesGlass else { return }
            withAnimation(.smooth) { glassVisible = true }
        }
    }

    /// The popup content on its background: one glass module unless the content draws its own modules, or the
    /// black material background without Liquid Glass.
    @ViewBuilder
    private var popupBody: some View {
        if usesGlass {
            LiquidGlassContainer(enabled: true, spacing: Constants.popupModuleSpacing) {
                let styled = content
                    .applying(!providesModules) {
                        $0.liquidGlassBackground(true, in: RoundedRectangle(cornerRadius: Constants.popupCornerRadius)) {
                            EmptyView()
                        }
                    }
                    .containerShape(RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
                if glassVisible {
                    styled.liquidGlassMaterializes()
                } else {
                    // Keep the size while hidden, so the popup is positioned before it materializes.
                    styled.hidden()
                }
            }
        } else {
            content
                .background(Color.black)
                .cornerRadius(((1.0 - animationValue) * 1) + 40)
        }
    }

    var computedOffset: CGFloat {
        let screenWidth = NSScreen.main?.frame.width ?? 0
        let W = viewFrame.width
        let M = viewFrame.midX
        let newLeft = (M - W / 2) - 20
        let newRight = (M + W / 2) + 20

        if newRight > screenWidth {
            return screenWidth - newRight
        } else if newLeft < 0 {
            return -newLeft
        }
        return 0
    }

    /// MenuBarPopup centers the popup on the bar's edge of the panel, so shift it by half its height into the screen.
    var computedYOffset: CGFloat {
        return isBottom ? -viewFrame.height / 2 : viewFrame.height / 2
    }
}

extension Notification.Name {
    static let willShowWindow = Notification.Name("willShowWindow")
    static let willHideWindow = Notification.Name("willHideWindow")
    static let willChangeContent = Notification.Name("willChangeContent")
}
