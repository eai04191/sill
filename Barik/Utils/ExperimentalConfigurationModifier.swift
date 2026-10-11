import SwiftUI

private struct ExperimentalConfigurationModifier: ViewModifier {
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    
    let horizontalPadding: CGFloat
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        Group {
            if !configManager.config.experimental.foreground.widgetsBackground.displayed {
                content
            } else {
                let radius = foregroundHeight < 30 ? 0 : cornerRadius
                let usesGlass = configManager.config.usesLiquidGlass
                content
                    .frame(height: foregroundHeight < 45 ? 30 : 38)
                    .padding(.horizontal, foregroundHeight < 45 && horizontalPadding != 15 ? 0 :
                                foregroundHeight < 30 ? 0 : horizontalPadding
                    )
                    // The bar's white text is meant to sit on the wallpaper. On glass, use the system primary color and let
                    // Liquid Glass adapt it to what is behind (dark over a light background). The hierarchical `.primary`
                    // style would resolve to the bar's white foreground style instead, so use `Color.primary`.
                    // glassEffect captures the content as styled so far, so this has to come before it.
                    .foregroundStyle(usesGlass ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.foregroundOutside))
                    .liquidGlassBackground(usesGlass, in: RoundedRectangle(cornerRadius: radius)) {
                        Rectangle().fill(configManager.config.experimental.foreground.widgetsBackground.blur)
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
