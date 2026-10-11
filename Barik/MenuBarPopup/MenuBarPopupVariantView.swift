import SwiftUI

enum MenuBarPopupVariant: String, Equatable {
    case box, vertical, horizontal
}

struct MenuBarPopupVariantView: View {
    private let box: AnyView?
    private let vertical: AnyView?
    private let horizontal: AnyView?

    var selectedVariant: MenuBarPopupVariant
    @State private var hovered = false
    @FocusState private var focusedVariant: MenuBarPopupVariant?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onVariantSelected: ((MenuBarPopupVariant) -> Void)?

    /// The layout buttons' symbol height, padding and distance from the popup's bottom edge.
    fileprivate static let buttonSymbolHeight: CGFloat = 10
    fileprivate static let buttonPadding: CGFloat = 8
    private static let buttonsBottomInset: CGFloat = 5
    /// The layout buttons sit in the bottom trailing corner, in the content's bottom padding, which is shorter than
    /// them; the content leaves the rest of their height below it, so the buttons never cover its last row, such as the
    /// calendar's last week.
    private static var contentBottomClearance: CGFloat {
        max(buttonSymbolHeight + buttonPadding * 2 + buttonsBottomInset - Constants.popupPadding, 0)
    }

    init(
        selectedVariant: MenuBarPopupVariant,
        onVariantSelected: ((MenuBarPopupVariant) -> Void)? = nil,
        @ViewBuilder box: () -> some View = { EmptyView() },
        @ViewBuilder vertical: () -> some View = { EmptyView() },
        @ViewBuilder horizontal: () -> some View = { EmptyView() }
    ) {
        self.selectedVariant = selectedVariant
        self.onVariantSelected = onVariantSelected

        let boxView = box()
        let verticalView = vertical()
        let horizontalView = horizontal()

        self.box = (boxView is EmptyView) ? nil : AnyView(boxView)
        self.vertical =
            (verticalView is EmptyView) ? nil : AnyView(verticalView)
        self.horizontal =
            (horizontalView is EmptyView) ? nil : AnyView(horizontalView)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content(for: shownVariant)
                .padding(.bottom, Self.contentBottomClearance)
                .transition(.opacity)
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 3) {
                if box != nil {
                    variantButton(
                        variant: .box, systemImageName: "square.inset.filled",
                        label: "Box layout")
                }
                if vertical != nil {
                    variantButton(
                        variant: .vertical,
                        systemImageName: "rectangle.portrait.inset.filled",
                        label: "Vertical layout")
                }
                if horizontal != nil {
                    variantButton(
                        variant: .horizontal,
                        systemImageName: "rectangle.inset.filled",
                        label: "Horizontal layout")
                }
            }
            .padding(.horizontal, Constants.popupPadding)
            .padding(.bottom, Self.buttonsBottomInset)
            .contentShape(Rectangle())
            // The buttons appear on hover. Show them also while one has keyboard focus and while VoiceOver runs, as
            // a hidden button cannot be seen when focused and is left out by VoiceOver.
            .opacity(hovered || focusedVariant != nil || voiceOverEnabled ? 1 : 0.0)
            .onHover { value in
                withAnimation(.easeIn(duration: 0.3)) {
                    hovered = value
                }
            }
        }
    }

    /// The variant shown: the selected one, or the first one this popup has when it has no view for the selected one,
    /// such as `view-variant = "box"` for a popup without a box layout, which would otherwise be empty.
    private var shownVariant: MenuBarPopupVariant {
        let available = [(MenuBarPopupVariant.box, box), (.vertical, vertical), (.horizontal, horizontal)]
            .filter { $0.1 != nil }
            .map(\.0)
        return available.contains(selectedVariant) ? selectedVariant : available.first ?? selectedVariant
    }

    @ViewBuilder
    private func content(for variant: MenuBarPopupVariant) -> some View {
        switch variant {
        case .box:
            if let view = box { view }
        case .vertical:
            if let view = vertical { view }
        case .horizontal:
            if let view = horizontal { view }
        }
    }

    private func variantButton(
        variant: MenuBarPopupVariant, systemImageName: String, label: LocalizedStringKey
    ) -> some View {
        Button {
            guard shownVariant != variant else { return }
            // The layouts cross-fade while the popup resizes, so the switch reads as the same popup changing size
            // (HIG, Popovers). Blurring the content out and back in is motion Reduce Motion asks to avoid, and with
            // Reduce Motion the layout switches at once.
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                onVariantSelected?(variant)
            }
        } label: {
            Image(systemName: systemImageName)
                .foregroundStyle(Color.primary.opacity(0.5))
                .frame(width: 13, height: Self.buttonSymbolHeight)
        }
        .buttonStyle(HoverButtonStyle())
        .focused($focusedVariant, equals: variant)
        .accessibilityLabel(label)
        .accessibilityAddTraits(shownVariant == variant ? .isSelected : [])
        .help(label)
        .overlay(
            Group {
                if shownVariant == variant {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                }
            }
        )
    }
}

private struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration)
    }

    struct HoverButton: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(MenuBarPopupVariantView.buttonPadding)
                .background(isHovered ? Color.gray.opacity(0.4) : Color.clear)
                .cornerRadius(8)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
}
