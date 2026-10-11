import SwiftUI

extension View {
    /// Inserts and removes the view with `.blurReplace`, or with a cross-fade when Reduce Motion is on, which asks to
    /// avoid blurring and scaling (HIG, Motion).
    func blurReplaceTransition() -> some View {
        modifier(BlurReplaceUnlessReduceMotion())
    }
}

private struct BlurReplaceUnlessReduceMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
    }
}
