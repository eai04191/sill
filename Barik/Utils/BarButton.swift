import SwiftUI

extension View {
    /// Makes a bar widget or popup control a button, so VoiceOver announces it with a label and value and can press it,
    /// while keeping its look. Widgets used tap gestures, which assistive technologies do not see as actionable.
    func barButton(label: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        modifier(BarButtonModifier(label: label, value: value, action: action))
    }

    /// Makes the whole frame of a bar widget receive clicks and hover. The bar window lets clicks on its transparent
    /// pixels through to the windows behind it, so only the widgets get an almost invisible fill; the space between
    /// them stays transparent and clicks there reach the app behind the bar.
    func barHitArea() -> some View {
        background(.black.opacity(0.001))
            .contentShape(Rectangle())
    }
}

/// A bar widget's button. With `button-style = "glass"` in the widget's config and Liquid Glass enabled, it is a
/// system glass button, which draws its own glass with the system's hover and press states; otherwise a plain button
/// on the widget's own glass (see `ExperimentalConfigurationModifier`). The option lets both be compared on the bar.
private struct BarButtonModifier: ViewModifier {
    let label: String
    let value: String?
    let action: () -> Void

    @Environment(\.barButtonUsesSystemGlass) private var usesSystemGlass
    @ObservedObject private var configManager = ConfigManager.shared

    func body(content: Content) -> some View {
        Group {
            if usesSystemGlass, configManager.config.usesLiquidGlass, #available(macOS 26.0, *) {
                // Widgets stretch their content to the bar's height to make the whole strip clickable, which the
                // glass button would wrap in its glass; keep the content at its own height so the glass is the chip.
                Button(action: action) {
                    content.fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                // A glass button gives up its margin when offered less than its width, which the bar's stack did to
                // the usage widget; widgets keep their width.
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Button(action: action) {
                    content.barHitArea()
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
}

private struct BarButtonUsesSystemGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the bar widget's button is a system glass button (`button-style = "glass"` in the widget's config).
    var barButtonUsesSystemGlass: Bool {
        get { self[BarButtonUsesSystemGlassKey.self] }
        set { self[BarButtonUsesSystemGlassKey.self] = newValue }
    }
}
