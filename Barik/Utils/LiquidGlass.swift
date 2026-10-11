import SwiftUI

// Liquid Glass for Barik's functional layer: widget backgrounds and popups.
//
// Following the HIG (Materials > Liquid Glass), glass is used only for these controls floating above
// the desktop and windows, with the regular variant, which keeps text legible over any background and
// follows the Reduce Transparency and Increase Contrast settings.

extension View {
    /// Draws the regular Liquid Glass in `shape` when enabled, or no glass otherwise.
    /// - Parameter interactive: For controls, makes the glass react to the pointer like system glass buttons.
    @ViewBuilder
    func liquidGlassBackground<S: Shape>(_ enabled: Bool, in shape: S, interactive: Bool = false) -> some View {
        if enabled {
            self.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            self
        }
    }

    /// Makes the glass in this view materialize in and out, the system transition for Liquid Glass appearing,
    /// when the view is inserted or removed inside a `LiquidGlassContainer`.
    func liquidGlassMaterializes() -> some View {
        glassEffectTransition(.materialize)
    }

    /// The regular glass behind a popup, or no glass when `enabled` is false. Switching between `.regular` and
    /// `.identity` keeps the view structure, so the content is not rebuilt when it turns out to draw its own modules.
    func popupGlass<S: Shape>(enabled: Bool, in shape: S) -> some View {
        glassEffect(enabled ? .regular : .identity, in: shape)
    }

}

extension NSWindow {
    /// Makes Liquid Glass in this window render as in an active window. AppKit draws glass in a window that is not key
    /// as frosted glass, which only blurs what is behind it, and Barik's bar never becomes key so it does not take the
    /// keyboard from the app in use. No public API changes this (overriding `isKeyWindow` or setting the SwiftUI
    /// `appearsActive` and `controlActiveState` environment values does not), so this uses the private
    /// `_setForceMainAppearance:`, which keeps the active look without making the window key. If a later macOS removes
    /// it, the window keeps the frosted glass.
    func setForcesActiveGlassAppearance(_ forces: Bool) {
        let selector = NSSelectorFromString("_setForceMainAppearance:")
        guard responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(method(for: selector), to: Setter.self)(self, selector, forces)
    }
}

/// Groups the bar's glass widgets so they render together, as the SwiftUI documentation recommends
/// for multiple Liquid Glass effects.
struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) { content }
    }
}
