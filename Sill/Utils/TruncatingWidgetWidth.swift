import SwiftUI

/// Lets a bar widget with long text, such as a song title or an event name, truncate the text to the room the bar has
/// instead of leaving the bar. The bar keeps the widgets whose ideal widths fit (see `MenuBarView.fittingRow`), so a
/// widget wider than its side was moved into the "more" widget whole, unlike other macOS text that does not fit.
///
/// Applied outside `barWidgetButton`, it gives the widget `minimumWidth` as its ideal width, so the bar keeps it when
/// that fits, and up to `fullWidth` when the bar has room. The glass button keeps its label at the label's own width
/// (see `BarWidgetButtonModifier`), so the widget limits its label to `availableWidth`, which this writes back.
/// Offered less than `minimumWidth`, the widget does not fit and moves into the "more" widget as before.
struct TruncatingWidgetWidth: ViewModifier {
    /// The label's width with its whole text, inside the glass button's margin.
    let fullWidth: CGFloat
    /// The narrowest the label gets by truncating its text.
    let minimumWidth: CGFloat
    let alignment: Alignment
    /// The width the label has inside the glass button's margin, at most `fullWidth`.
    @Binding var availableWidth: CGFloat

    func body(content: Content) -> some View {
        let margin = GlassButtonInset.regular.width * 2
        // Before the label is measured the widget keeps its own size.
        let measured = fullWidth > 0
        let minimum = measured ? min(fullWidth, minimumWidth) + margin : nil
        // The frame's size depends only on these widths and the offered width, not on the label inside it, so the
        // label taking the written-back width does not change it again.
        content
            .frame(
                minWidth: minimum, idealWidth: minimum, maxWidth: measured ? fullWidth + margin : nil,
                alignment: alignment)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                availableWidth = width - margin
            }
    }
}
