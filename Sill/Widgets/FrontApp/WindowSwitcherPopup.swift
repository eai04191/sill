import AppKit
import SwiftUI

/// Lists the windows on every AeroSpace workspace like a menu, grouped by app, with a search field that filters them as
/// the user types. Up and Down move the selection, Return or a click focuses the selected window, and Escape closes.
struct WindowSwitcherPopup: View {
    @StateObject private var model = WindowSwitcherModel()
    @State private var query = ""
    @State private var selectedID: Int?
    /// Where the mouse pointer was when it last selected a row, or when the keyboard last moved the selection. Rows
    /// scrolling under a pointer that stays still report hovering too, which must not take the selection from the
    /// keyboard.
    @State private var selectingMouseLocation: NSPoint?
    @State private var listHeight: CGFloat = 0
    @FocusState private var isSearchFocused: Bool

    private static let width: CGFloat = 360
    private static let maxListHeight: CGFloat = 420

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                searchField(proxy: proxy)
                if model.focusFailed {
                    message("Could not switch to the window")
                }
                content
            }
            .onChange(of: query) { resetSelection(proxy: proxy) }
            .onChange(of: model.state) { resetSelection(proxy: proxy) }
        }
        .frame(width: Self.width, alignment: .leading)
        .padding(Constants.popupPadding)
        .task { await model.load() }
        // MenuBarPopup leaves the initial focus alone for this popup (`focusesContent`), so nothing clears it after
        // the field takes it. Focusing waits a turn of the run loop, until the field is in the panel.
        .onAppear {
            DispatchQueue.main.async { isSearchFocused = true }
        }
    }

    // MARK: - Search

    private func searchField(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search windows", text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search windows")
                .focused($isSearchFocused)
                .onSubmit { focusSelectedWindow() }
                .onKeyPress(.upArrow) { moveSelection(by: -1, proxy: proxy) }
                .onKeyPress(.downArrow) { moveSelection(by: 1, proxy: proxy) }
                .onKeyPress(.escape) {
                    // Escape first ends an input method's conversion, as it does in any text field.
                    guard !isComposingText else { return .ignored }
                    MenuBarPopup.hide()
                    return .handled
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Whether an input method is converting text in the search field, which uses the arrow keys and Escape itself.
    private var isComposingText: Bool {
        let window = NSApp.windows.first { $0.isKeyWindow }
        return (window?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        case .failed(.notInstalled):
            message("AeroSpace is not available")
        case .failed(.commandFailed):
            message("Could not get the windows from AeroSpace")
        case .loaded(let windows) where windows.isEmpty:
            message("No windows")
        case .loaded:
            if groups.isEmpty {
                message("No matching windows")
            } else {
                list
            }
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    Text(group.appName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.top, group.id == groups.first?.id ? 0 : 8)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.windows) { window in
                        row(window)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        // The list is as tall as its rows up to the maximum, and scrolls beyond it.
        .frame(height: min(listHeight, Self.maxListHeight))
        // An overlay scroller is drawn over the content and would cover the workspace names, so the scroll view
        // reaches into the popup's padding by the scroller's width and keeps the rows out of it: the scroller then
        // shows in the padding and the rows keep their width.
        .contentMargins(.trailing, scrollerGutter, for: .scrollContent)
        .padding(.trailing, -scrollerGutter)
        .scrollIndicators(.automatic)
    }

    /// The width of an overlay scroller. A legacy scroller takes its own room beside the content.
    private var scrollerGutter: CGFloat {
        guard NSScroller.preferredScrollerStyle == .overlay else { return 0 }
        return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)
    }

    private func row(_ window: AeroSpaceWindow) -> some View {
        let isSelected = window.id == selectedID
        return Button {
            Task { await model.focus(window) }
        } label: {
            HStack(spacing: 8) {
                // The app's name heads the group and is read in the row's label.
                Group {
                    if let icon = window.bundleIdentifier.flatMap({ model.icons[$0] }) {
                        Image(nsImage: icon).resizable()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
                Text(window.displayTitle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WidthLimit(maxWidth: 120) {
                    Text(window.workspace)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
                .layoutPriority(1)
                    .padding(.leading, 4)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            guard case .active = phase else { return }
            let location = NSEvent.mouseLocation
            guard location != selectingMouseLocation else { return }
            selectingMouseLocation = location
            selectedID = window.id
        }
        .accessibilityLabel(
            String(
                localized: "\(window.displayTitle), \(window.appName), workspace \(window.workspace)",
                comment: "VoiceOver label of a window in the window switcher: the window title, app and workspace."))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(window.id)
    }

    // MARK: - Filtering and selection

    private struct AppGroup: Identifiable {
        let appName: String
        let windows: [AeroSpaceWindow]
        var id: String { appName }
    }

    private var windows: [AeroSpaceWindow] {
        if case .loaded(let windows) = model.state { return windows }
        return []
    }

    /// The windows matching the search, grouped by app: apps in Finder's name order, and each app's windows by title.
    private var groups: [AppGroup] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty ? windows : windows.filter { window in
            [window.title, window.appName, window.workspace].contains { Self.text($0, contains: query) }
        }
        return Dictionary(grouping: matches, by: \.appName)
            .map { appName, windows in
                AppGroup(
                    appName: appName,
                    windows: windows.sorted { lhs, rhs in
                        switch lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) {
                        case .orderedAscending: true
                        case .orderedDescending: false
                        case .orderedSame: lhs.id < rhs.id
                        }
                    })
            }
            .sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
    }

    /// Matches regardless of case, accents, and full or half width, so "ｆｉｒｅ" finds Firefox.
    private static func text(_ text: String, contains query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            != nil
    }

    /// The rows in the order they are shown.
    private var visibleWindows: [AeroSpaceWindow] { groups.flatMap(\.windows) }

    private func resetSelection(proxy: ScrollViewProxy) {
        selectedID = visibleWindows.first?.id
        if let selectedID {
            proxy.scrollTo(selectedID)
        }
    }

    private func moveSelection(by offset: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !isComposingText else { return .ignored }
        let visible = visibleWindows
        guard !visible.isEmpty else { return .handled }
        let current = visible.firstIndex { $0.id == selectedID }
        let index = current.map { min(max($0 + offset, 0), visible.count - 1) } ?? 0
        selectedID = visible[index].id
        selectingMouseLocation = NSEvent.mouseLocation
        // Without an anchor, the list scrolls only as far as needed to show the row.
        proxy.scrollTo(visible[index].id)
        return .handled
    }

    private func focusSelectedWindow() {
        guard let window = visibleWindows.first(where: { $0.id == selectedID }) else { return }
        Task { await model.focus(window) }
    }
}

/// Makes its content as wide as it needs, up to `maxWidth` and the width offered. A `frame(maxWidth:)` grows to the
/// width it is offered instead, which gave a one-letter workspace name the whole 120 points and cut the title short.
private struct WidthLimit: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = min(proposal.width ?? maxWidth, maxWidth)
        return subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
