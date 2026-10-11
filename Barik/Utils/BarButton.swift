import SwiftUI

extension View {
    /// Makes a popup control a button, so VoiceOver announces it with a label and value and can press it, while
    /// keeping its look. Bar widgets use `barWidgetButton(label:value:action:)`.
    func barButton(label: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            self.barHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }

    /// Makes a bar widget a button. With Liquid Glass it is a system glass button, which draws the widget's glass
    /// with the system's hover and press states, the same at every width; the HIG asks custom buttons for a press
    /// state, which the widgets' own interactive glass barely showed. Without Liquid Glass it is a plain button on the
    /// widget's material background.
    func barWidgetButton(label: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        modifier(BarWidgetButtonModifier(label: label, value: value, action: action))
    }

    /// Makes the whole frame of a bar widget receive clicks and hover. The bar window lets clicks on its transparent
    /// pixels through to the windows behind it, so only the widgets get an almost invisible fill; the space between
    /// them stays transparent and clicks there reach the app behind the bar.
    func barHitArea() -> some View {
        background(.black.opacity(0.001))
            .contentShape(Rectangle())
    }
}

private struct BarWidgetButtonModifier: ViewModifier {
    let label: String
    let value: String?
    let action: () -> Void

    @ObservedObject private var configManager = ConfigManager.shared

    func body(content: Content) -> some View {
        Group {
            if configManager.config.usesLiquidGlass, #available(macOS 26.0, *) {
                // Widgets stretch their content to the bar's height to make the whole strip clickable, which the
                // glass button would wrap in its glass; keep the content at its own height so the glass is the chip.
                Button(action: action) {
                    content
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.widgetGlassIsButton, true)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                // A glass button gives up its margin when offered less than its width, which the bar's stack did to
                // the usage widget; widgets keep their width.
                .fixedSize(horizontal: true, vertical: false)
            } else {
                content.barButton(label: label, value: value, action: action)
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
}

private struct WidgetGlassIsButtonKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the widget's glass is drawn by the system glass button around it (see `barWidgetButton`), so the
    /// widget draws none itself and leaves room for the button's margin (see `GlassButtonInset`).
    var widgetGlassIsButton: Bool {
        get { self[WidgetGlassIsButtonKey.self] }
        set { self[WidgetGlassIsButtonKey.self] = newValue }
    }
}
