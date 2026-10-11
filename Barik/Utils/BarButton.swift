import SwiftUI

extension View {
    /// Makes a bar widget or popup control a button, so VoiceOver announces it with a label and value and can press it,
    /// while keeping its look. Widgets used tap gestures, which assistive technologies do not see as actionable.
    func barButton(label: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            self.barHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }

    /// Makes the whole frame of a bar widget receive clicks and hover. The bar window lets clicks on its transparent
    /// pixels through to the windows behind it, so only the widgets get an almost invisible fill; the space between
    /// them stays transparent and clicks there reach the app behind the bar.
    func barHitArea() -> some View {
        background(.black.opacity(0.001))
            .contentShape(Rectangle())
    }
}
