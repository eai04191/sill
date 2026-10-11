import SwiftUI

// Liquid Glass (macOS 26+) for Barik's functional layer: widget backgrounds and popups.
//
// Following the HIG (Materials > Liquid Glass), glass is used only for these controls floating above
// the desktop and windows, with the regular variant, which keeps text legible over any background and
// follows the Reduce Transparency and Increase Contrast settings. Barik keeps its previous material
// look when `liquid-glass` is off or on earlier macOS versions.

extension Config {
    /// Whether Liquid Glass is enabled in the config and available on this macOS.
    var usesLiquidGlass: Bool {
        guard rootToml.liquidGlass == true else { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

extension View {
    /// Draws the regular Liquid Glass in `shape` when enabled, or `fallback` behind the view otherwise.
    /// - Parameter interactive: For controls, makes the glass react to the pointer like system glass buttons.
    @ViewBuilder
    func liquidGlassBackground<S: Shape, Fallback: View>(
        _ enabled: Bool, in shape: S, interactive: Bool = false, @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        if enabled, #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            self.background(fallback())
        }
    }
}

extension View {
    /// Applies `transform` only when `condition` holds. Used to leave out modifiers such as clipping, shadows and
    /// blurs around Liquid Glass: they rasterize or clip its rectangular bounds, including the soft shadow and edge
    /// highlight the glass draws outside its shape, which shows up as a square frame around the rounded glass.
    @ViewBuilder
    func applying<Modified: View>(_ condition: Bool, _ transform: (Self) -> Modified) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

/// Groups the bar's glass widgets so they render together, as the SwiftUI documentation recommends
/// for multiple Liquid Glass effects. Without Liquid Glass it just shows the content.
struct LiquidGlassContainer<Content: View>: View {
    let enabled: Bool
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if enabled, #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
