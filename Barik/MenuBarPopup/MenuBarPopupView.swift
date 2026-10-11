import SwiftUI

struct MenuBarPopupView<Content: View>: View {
    let content: Content

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    private var isBottom: Bool { configManager.config.position == .bottom }
    private var usesGlass: Bool { configManager.config.usesLiquidGlass }

    @State private var viewFrame: CGRect = .zero
    @State private var animationValue: Double = 0.01
    private var animated: Bool { isShowAnimation || isHideAnimation }
    @State private var isShowAnimation = false
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

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
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
                    // Glass popups fade out with their window (see MenuBarPopup); the scale and blur below are for the
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
                    // Glass popups fade out with their window (see MenuBarPopup); the scale and blur below are for the
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
                        }
                    }
                    .onChange(of: geometry.size) { _, __ in
                        viewFrame = geometry.frame(in: .global)
                    }
            }
        )
        // Popups are always dark: the material popup draws a black background, and glass popups are dark like the
        // Control Center (MenuBarPopup gives their window the dark appearance, which the glass follows).
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
        .onPreferenceChange(PopupProvidesGlassModulesKey.self) { providesModules = $0 }
        // MenuBarPopup builds a new view for every popup and may post willShowWindow before this view subscribes,
        // so also materialize the glass when the view appears. The offset is not animated while it appears.
        .onAppear {
            guard usesGlass else { return }
            isShowAnimation = true
            withAnimation(.smooth) { glassVisible = true }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Constants.menuBarPopupAnimationDurationInMilliseconds)
            ) {
                isShowAnimation = false
            }
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

