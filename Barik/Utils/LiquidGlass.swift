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

    /// Makes the glass in this view materialize in and out, the system transition for Liquid Glass appearing,
    /// when the view is inserted or removed inside a `LiquidGlassContainer`.
    @ViewBuilder
    func liquidGlassMaterializes() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectTransition(.materialize)
        } else {
            self
        }
    }

    /// The regular glass behind a popup, or no glass when `enabled` is false. Switching between `.regular` and
    /// `.identity` keeps the view structure, so the content is not rebuilt when it turns out to draw its own modules.
    @ViewBuilder
    func popupGlass<S: Shape>(enabled: Bool, in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(enabled ? .regular : .identity, in: shape)
        } else {
            self
        }
    }

    /// Marks popup content that draws its own glass modules, so the popup does not add glass behind them
    /// (glass on glass, which the HIG asks to avoid).
    func popupProvidesGlassModules() -> some View {
        preference(key: PopupProvidesGlassModulesKey.self, value: true)
    }
}

struct PopupProvidesGlassModulesKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
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

extension NSWindow {
    /// Makes Liquid Glass in this window render as in an active window. AppKit draws glass in a window that is not key
    /// as frosted glass, which only blurs what is behind it, and Barik's bar never becomes key so it does not take the
    /// keyboard from the app in use. No public API changes this (overriding `isKeyWindow` or setting the SwiftUI
    /// `appearsActive` and `controlActiveState` environment values does not), so this uses the private
    /// `_setForceMainAppearance:`, which keeps the active look without making the window key. Callers turn it on only
    /// with Liquid Glass enabled and off when it is disabled, so the private API is not used without glass. If a later
    /// macOS removes it, the window keeps the frosted glass.
    func setForcesActiveGlassAppearance(_ forces: Bool) {
        let selector = NSSelectorFromString("_setForceMainAppearance:")
        guard responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(method(for: selector), to: Setter.self)(self, selector, forces)
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
