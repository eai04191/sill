import SwiftUI

extension View {
    /// Makes a bar widget or popup control a button, so VoiceOver announces it with a label and value and can press it,
    /// while keeping its look. Widgets used tap gestures, which assistive technologies do not see as actionable.
    func barButton(label: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            self.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Popup panels become key when shown, which otherwise draws a focus ring around the first button.
        .focusEffectDisabled()
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
}
