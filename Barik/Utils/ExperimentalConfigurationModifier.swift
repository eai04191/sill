import SwiftUI

/// The height of a widget on the bar: 4 points short of the bar's edges, at most 38 points. A fixed height overflowed
/// a bar lower than the widget, where the glass behind it was not drawn.
func barWidgetHeight(forBarHeight barHeight: CGFloat) -> CGFloat {
    min(38, max(16, barHeight - 8))
}

private struct ExperimentalConfigurationModifier: ViewModifier {
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    
    let horizontalPadding: CGFloat
    let cornerRadius: CGFloat
    /// A system glass button draws the widget's glass itself (see `BarButtonModifier`).
    @Environment(\.barButtonUsesSystemGlass) private var usesSystemGlassButton
    
    func body(content: Content) -> some View {
        Group {
            if !configManager.config.experimental.foreground.widgetsBackground.displayed {
                content
            } else {
                let radius = foregroundHeight < 30 ? 0 : cornerRadius
                let usesGlass = configManager.config.usesLiquidGlass
                // A system glass button adds its own margin around the content, so the content is that much smaller
                // and the widget keeps the size it has with its own glass.
                let buttonInset = usesGlass && usesSystemGlassButton ? GlassButtonInset.regular : .zero
                let padding: CGFloat = foregroundHeight < 30 ? 8 :
                    foregroundHeight < 45 && horizontalPadding != 15 ? 0 : horizontalPadding
                content
                    .frame(height: barWidgetHeight(forBarHeight: foregroundHeight) - buttonInset.height * 2)
                    // On a bar under 30 points the widget still gets a little room around its content, so its background
                    // does not shrink to the text.
                    // Below the button's margin the padding is negative, which takes the rest out of the margin.
                    .padding(.horizontal, padding - buttonInset.width)
                    // The bar's white text is meant to sit on the wallpaper. On glass, use the system primary color and let
                    // Liquid Glass adapt it to what is behind (dark over a light background). The hierarchical `.primary`
                    // style would resolve to the bar's white foreground style instead, so use `Color.primary`.
                    // glassEffect captures the content as styled so far, so this has to come before it.
                    .foregroundStyle(usesGlass ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.foregroundOutside))
                    // Bar widgets are buttons, so their glass reacts to the pointer. Glass widgets are capsules like the
                    // now playing widget, which is always one; the corner radius would leave a 38-point widget with
                    // 15-point corners next to it.
                    .liquidGlassBackground(usesGlass && !usesSystemGlassButton, in: Capsule(), interactive: true) {
                        if !usesGlass {
                            Rectangle().fill(configManager.config.experimental.foreground.widgetsBackground.blur)
                        }
                    }
                    .applying(!usesGlass) { $0.cornerRadius(radius) }
                    // Liquid Glass draws its own edge highlight, so the outline is only for the material look.
                    .overlay(
                        foregroundHeight < 30 || usesGlass ? nil :
                            Capsule().stroke(Color.noActive, lineWidth: 1)
                    )
            }
        }.scaleEffect(foregroundHeight < 25 ? 0.9 : 1, anchor: .leading)
    }
}

extension View {
    func experimentalConfiguration(
        horizontalPadding: CGFloat = 15,
        cornerRadius: CGFloat
    ) -> some View {
        self.modifier(ExperimentalConfigurationModifier(
            horizontalPadding: horizontalPadding,
            cornerRadius: cornerRadius
        ))
    }
}

/// The margin a system glass button (`.glass`, capsule, regular control size) adds on each side of its content,
/// measured with NSHostingView on macOS 26: 12 points on the left and right and 4 above and below, whatever the
/// content's size.
enum GlassButtonInset {
    static let regular = CGSize(width: 12, height: 4)
}
