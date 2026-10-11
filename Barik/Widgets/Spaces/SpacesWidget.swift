import SwiftUI

struct SpacesWidget: View {
    @StateObject var viewModel = SpacesViewModel.inUse.instance { SpacesViewModel() }

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {
        HStack(spacing: foregroundHeight < 30 ? 0 : 8) {
            ForEach(viewModel.spaces) { space in
                SpaceView(space: space)
            }
        }
        .experimentalConfiguration(horizontalPadding: 5, cornerRadius: 10)
        .animation(.smooth(duration: 0.3), value: viewModel.spaces)
        .foregroundStyle(Color.foreground)
        .environmentObject(viewModel)
    }
}

/// This view shows a space with its windows.
private struct SpaceView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @EnvironmentObject var viewModel: SpacesViewModel

    var config: ConfigData { configProvider.config }
    var spaceConfig: ConfigData { config["space"]?.dictionaryValue ?? [:] }

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var showKey: Bool { spaceConfig["show-key"]?.boolValue ?? true }

    let space: AnySpace

    var body: some View {
        let isFocused = space.windows.contains { $0.isFocused } || space.isFocused
        HStack(spacing: 0) {
            Spacer().frame(width: 10)
            if showKey {
                Text(space.id)
                    .font(.headline)
                    .frame(minWidth: 15)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer().frame(width: 5)
            }
            HStack(spacing: 2) {
                ForEach(space.windows) { window in
                    WindowView(window: window, space: space)
                }
            }
            Spacer().frame(width: 10)
        }
        .frame(height: 30)
        .background(
            foregroundHeight < 30 ?
            (isFocused
             ? Color.noActive
             : Color.clear) :
                (isFocused
                 ? Color.active
                 : Color.noActive)
        )
        .clipShape(RoundedRectangle(cornerRadius: foregroundHeight < 30 ? 0 : 8, style: .continuous))
        .shadow(color: .shadow, radius: foregroundHeight < 30 ? 0 : 2)
        .transition(.blurReplace)
        .onTapGesture {
            viewModel.switchToSpace(space, needWindowFocus: true)
        }
        // The space contains tappable windows, so it keeps the tap gesture instead of becoming a button with nested
        // buttons, and exposes the same action to VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Space \(space.id)")
        .accessibilityAction {
            viewModel.switchToSpace(space, needWindowFocus: true)
        }
    }
}

/// This view shows a window and its icon.
private struct WindowView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @EnvironmentObject var viewModel: SpacesViewModel

    var config: ConfigData { configProvider.config }
    var windowConfig: ConfigData { config["window"]?.dictionaryValue ?? [:] }
    var titleConfig: ConfigData {
        windowConfig["title"]?.dictionaryValue ?? [:]
    }

    var showTitle: Bool { windowConfig["show-title"]?.boolValue ?? true }
    var maxLength: Int { titleConfig["max-length"]?.intValue ?? 50 }
    /// The widest a focused window's title gets: `max-length` times the average width of a lowercase Latin letter in
    /// the title font. A Latin title gets about as many characters as before, and wide characters such as CJK take
    /// more of the width, so no title gets wider than this.
    var maxTitleWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let letterWidth = (letters as NSString).size(withAttributes: [.font: font]).width / CGFloat(letters.count)
        return CGFloat(maxLength) * letterWidth
    }
    var alwaysDisplayAppTitleFor: [String] { titleConfig["always-display-app-name-for"]?.arrayValue?.filter({ $0.stringValue != nil }).map { $0.stringValue! } ?? [] }

    let window: AnyWindow
    let space: AnySpace

    @State var isHovered = false

    var body: some View {
        let size: CGFloat = 21
        let sameAppCount = space.windows.filter { $0.appName == window.appName }
            .count
        let title = sameAppCount > 1 && !alwaysDisplayAppTitleFor.contains { $0 == window.appName } ? window.title : (window.appName ?? "")
        let spaceIsFocused = space.windows.contains { $0.isFocused }
        HStack {
            ZStack {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: size, height: size)
                        .shadow(
                            color: .iconShadow,
                            radius: 2
                        )
                } else {
                    Image(systemName: "questionmark.circle")
                        .resizable()
                        .frame(width: size, height: size)
                }
            }
            .opacity(spaceIsFocused && !window.isFocused ? 0.5 : 1)
            .transition(.blurReplace)

            if window.isFocused, !title.isEmpty, showTitle {
                HStack {
                    MaxWidthLayout(maxWidth: maxTitleWidth) {
                        Text(title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .shadow(color: .foregroundShadow, radius: 3)
                    .fontWeight(.semibold)
                    Spacer().frame(width: 5)
                }
                .transition(.blurReplace)
            }
        }
        .padding(.all, 2)
        .background(isHovered || (!showTitle && window.isFocused) ? .selected : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.smooth, value: isHovered)
        .frame(height: 30)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(window.isFocused ? [.isButton, .isSelected] : .isButton)
        // A window without an app name is labeled with its title, which is then not read again as the value.
        .accessibilityLabel(window.appName ?? window.title)
        .accessibilityValue(window.appName == nil ? "" : window.title)
        .accessibilityAction {
            viewModel.switchToWindow(window, in: space)
        }
        .onTapGesture {
            viewModel.switchToWindow(window, in: space)
        }
        .onHover { value in
            isHovered = value
        }
    }
}

/// Lays out its only subview at most `maxWidth` wide, even when offered unlimited width, as when the bar measures
/// whether its widgets fit. A long title is then truncated instead of widening the bar.
private struct MaxWidthLayout: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = min(proposal.width ?? maxWidth, maxWidth)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
