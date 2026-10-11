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
    @State private var animationValue = 0.0

    var onVariantSelected: ((MenuBarPopupVariant) -> Void)?

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
                .blur(radius: animationValue * 30)
                .transition(.opacity)
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 3) {
                if box != nil {
                    variantButton(
                        variant: .box, systemImageName: "square.inset.filled")
                }
                if vertical != nil {
                    variantButton(
                        variant: .vertical,
                        systemImageName: "rectangle.portrait.inset.filled")
                }
                if horizontal != nil {
                    variantButton(
                        variant: .horizontal,
                        systemImageName: "rectangle.inset.filled")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 5)
            .contentShape(Rectangle())
            .opacity(hovered ? 1 : 0.0)
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
        variant: MenuBarPopupVariant, systemImageName: String
    ) -> some View {
        Button {
            if shownVariant != variant {
                withAnimation(.smooth(duration: 0.3)) {
                    animationValue = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.smooth(duration: 0.3)) {
                        onVariantSelected?(variant)
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.smooth(duration: 0.3)) {
                        animationValue = 0
                    }
                }
            }
        } label: {
            Image(systemName: systemImageName)
                .foregroundStyle(Color.primary.opacity(0.5))
                .frame(width: 13, height: 10)
        }
        .buttonStyle(HoverButtonStyle())
        .overlay(
            Group {
                if shownVariant == variant {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                        .opacity(1 - animationValue * 10)
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
                .padding(8)
                .background(isHovered ? Color.gray.opacity(0.4) : Color.clear)
                .cornerRadius(8)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
}
