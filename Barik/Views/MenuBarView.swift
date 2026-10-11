import SwiftUI

struct MenuBarView: View {
    @ObservedObject var configManager = ConfigManager.shared

    var body: some View {
        // With the system theme, glass widgets are dark glass with white text like the glass popups and the Control
        // Center. The HIG has small glass elements adapt to the content behind them, but only system components do
        // that; custom glass keeps the window's appearance whatever is behind it. The window appearance decides how
        // the glass is drawn, so it is set with preferredColorScheme.
        let theme: ColorScheme? =
            switch configManager.config.rootToml.theme {
            case "dark":
                .dark
            case "light":
                .light
            default:
                .dark
            }

        let items = configManager.config.rootToml.widgets.displayed

        let showsBanner = !items.contains(where: { $0.id == "system-banner" })

        let spacing = configManager.config.experimental.foreground.spacing

        if let sections = CenteredSections(items) {
            // Spacers split the free width between the sides, which only centers the middle widgets when both sides
            // are equally wide. Place them at the center of the whole bar (including the banner) instead, and keep
            // the sides to the space next to them. Widgets that do not fit are left out, nearest to the center first,
            // like status items in the macOS menu bar; clipping does not work because glass and the content on it
            // are drawn outside the clip. When the trailing side cannot fit even its "more" widget, its widgets are
            // put in the leading side's "more" widget instead. A layout cannot move views between the sides, so the
            // leading side is also built with them added, and CenteredBarLayout shows the variants that fit.
            CenteredBarLayout(spacing: spacing) {
                leadingSide(sections.leading, adding: [])
                LiquidGlassContainer(spacing: spacing) {
                    row(sections.centered)
                }
                trailingSide(sections.trailing, showsBanner: showsBanner)
                leadingSide(sections.leading, adding: sections.trailing)
                trailingSide([], showsBanner: showsBanner)
            }
            .modifier(BarFrame(configManager: configManager, theme: theme))
        } else {
            LiquidGlassContainer(spacing: spacing) {
                HStack(spacing: 0) {
                    row(items)
                    if showsBanner {
                        SystemBannerWidget(withLeftPadding: true)
                    }
                }
            }
            .modifier(BarFrame(configManager: configManager, theme: theme))
        }
    }

    /// The leading side of the centered layout, with `moved` (the trailing side's widgets) added to its "more" widget.
    private func leadingSide(_ items: [TomlWidgetItem], adding moved: [TomlWidgetItem]) -> some View {
        LiquidGlassContainer(spacing: configManager.config.experimental.foreground.spacing) {
            fittingRow(items, dropping: .trailing, adding: moved)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(HiddenFromAccessibilityWhenOffscreen())
    }

    /// The trailing side of the centered layout with the system banner.
    private func trailingSide(_ items: [TomlWidgetItem], showsBanner: Bool) -> some View {
        LiquidGlassContainer(spacing: configManager.config.experimental.foreground.spacing) {
            HStack(spacing: 0) {
                fittingRow(items, dropping: .leading)
                if showsBanner {
                    SystemBannerWidget(withLeftPadding: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .modifier(HiddenFromAccessibilityWhenOffscreen())
    }

    /// The widgets that fit the offered width: all of them, or fewer by leaving out widgets from the given edge. The
    /// left-out widgets are kept in a "more" widget on that edge, which shows them in a popup, together with `moved`,
    /// the other side's widgets in bar order. When even the "more" widget does not fit, ViewThatFits still shows it,
    /// and CenteredBarLayout moves the side away.
    private func fittingRow(
        _ items: [TomlWidgetItem], dropping edge: HorizontalEdge, adding moved: [TomlWidgetItem] = []
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach(0...items.count, id: \.self) { dropped in
                let shown = edge == .trailing ? Array(items.prefix(items.count - dropped)) : Array(items.suffix(items.count - dropped))
                let hidden = edge == .trailing ? Array(items.suffix(dropped)) + moved : moved + Array(items.prefix(dropped))
                HStack(spacing: configManager.config.experimental.foreground.spacing) {
                    if edge == .leading, !hidden.isEmpty { moreWidget(hidden, droppedFrom: edge) }
                    row(shown)
                    if edge == .trailing, !hidden.isEmpty { moreWidget(hidden, droppedFrom: edge) }
                }
            }
        }
    }

    /// The "more" widget of one side. Each side has its own popup identifier, so clicking the other side's "more"
    /// widget switches the popup instead of closing it.
    private func moreWidget(_ items: [TomlWidgetItem], droppedFrom edge: HorizontalEdge) -> some View {
        MoreWidgetsWidget(count: items.count, id: "more-widgets-\(edge == .trailing ? "leading" : "trailing")") {
            MoreWidgetsPopup(items: items, view: { AnyView(buildView(for: $0)) })
        }
    }

    private func row(_ items: [TomlWidgetItem]) -> some View {
        HStack(spacing: configManager.config.experimental.foreground.spacing) {
            ForEach(0..<items.count, id: \.self) { index in
                buildView(for: items[index])
            }
        }
    }

    @ViewBuilder
    private func buildView(for item: TomlWidgetItem) -> some View {
        let config = ConfigProvider(
            config: configManager.resolvedWidgetConfig(for: item))

        switch item.id {
        case "default.spaces":
            SpacesWidget().environmentObject(config)

        case "default.network":
            NetworkWidget().environmentObject(config)

        case "default.battery":
            BatteryWidget().environmentObject(config)

        case "default.time":
            TimeWidget(calendarManager: CalendarManager.shared(for: config))
                .environmentObject(config)
            
        case "default.nowplaying":
            NowPlayingWidget()
                .environmentObject(config)

        case "default.usage":
            UsageWidget()
                .environmentObject(config)

        case "default.volume":
            VolumeWidget()
                .environmentObject(config)

        case "default.frontapp":
            FrontAppWidget()
                .environmentObject(config)

        case "spacer":
            Spacer().frame(minWidth: 50, maxWidth: .infinity)

        case "divider":
            Rectangle()
                .fill(Color.active)
                .frame(width: 2, height: 15)
                .clipShape(Capsule())

        case "system-banner":
            SystemBannerWidget()

        case "center":
            // A marker for CenteredSections, not a widget. Without exactly two markers the widgets are laid out in
            // one row, and the markers are left out of it.
            EmptyView()

        default:
            Text("?\(item.id)?").foregroundColor(.red)
        }
    }
}

/// Splits the displayed widgets at two "center" markers: widgets before the first are leading, widgets between them
/// are centered on the bar, and widgets after the second are trailing. Nil without exactly two markers, which keeps
/// the original single row.
private struct CenteredSections {
    let leading: [TomlWidgetItem]
    let centered: [TomlWidgetItem]
    let trailing: [TomlWidgetItem]

    init?(_ items: [TomlWidgetItem]) {
        let markers = items.indices.filter { items[$0].id == "center" }
        guard markers.count == 2 else { return nil }
        leading = Array(items[..<markers[0]])
        centered = Array(items[(markers[0] + 1)..<markers[1]])
        trailing = Array(items[(markers[1] + 1)...])
    }
}

/// Places the views of the centered layout on the bar: the centered widgets (the second view) at the center of the
/// whole width, and one variant of each side next to them, limited to the space between the bar edge and the centered
/// widgets so they never overlap them. The sides are, in order: the leading side, the trailing side, the leading side
/// with the trailing side's widgets, and the trailing side with only the system banner.
private struct CenteredBarLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 5 else { return }
        let centered = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: bounds.height))
        let side = max(0, (bounds.width - centered.width) / 2 - spacing)
        let sideProposal = ProposedViewSize(width: side, height: bounds.height)
        subviews[1].place(
            at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(centered))
        let shown = shownSides(subviews, in: sideProposal)
        for index in [0, 3] {
            subviews[index].place(
                at: index == shown.leading ? CGPoint(x: bounds.minX, y: bounds.midY) : offscreen,
                anchor: .leading, proposal: sideProposal)
        }
        for index in [2, 4] {
            subviews[index].place(
                at: index == shown.trailing ? CGPoint(x: bounds.maxX, y: bounds.midY) : offscreen,
                anchor: .trailing, proposal: sideProposal)
        }
    }

    /// The indices of the side variants to show, nil for a side that shows nothing. When the trailing side cannot fit
    /// even its "more" widget, the leading side shows the trailing side's widgets in its "more" widget if that still
    /// fits, and the trailing side keeps only the system banner. The leading side never hands its widgets to the
    /// trailing side: both sides get the same width, and the trailing side's "more" widget needs the banner's width
    /// on top of the room the leading side's lacked. The decision only depends on the bar width and the widgets, not
    /// on which variants were shown before, so it cannot flip back and forth. When neither side can fit a "more"
    /// widget, the widgets of a side that does not fit cannot be reached.
    private func shownSides(_ subviews: Subviews, in proposal: ProposedViewSize) -> (leading: Int?, trailing: Int?) {
        let leadingFits = fits(subviews[0], in: proposal)
        let trailingFits = fits(subviews[2], in: proposal)
        let leading = leadingFits ? (!trailingFits && fits(subviews[3], in: proposal) ? 3 : 0) : nil
        let trailing = trailingFits ? 2 : (fits(subviews[4], in: proposal) ? 4 : nil)
        return (leading, trailing)
    }

    /// Whether a side is no wider than its space. ViewThatFits shows its last candidate even when it does not fit,
    /// and widgets with fixed-size text do not shrink, so a side can still be wider than offered.
    private func fits(_ subview: LayoutSubview, in proposal: ProposedViewSize) -> Bool {
        subview.sizeThatFits(proposal).width <= (proposal.width ?? 0) + 0.5
    }

    /// Where a side that does not fit is placed so it is not drawn over the centered widgets. A layout cannot remove
    /// a subview, and clipping does not hide Liquid Glass, so it is moved outside the bar's window instead, where
    /// `HiddenFromAccessibilityWhenOffscreen` hides it from VoiceOver.
    private let offscreen = CGPoint(x: -100_000, y: 0)
}

/// Hides a side that CenteredBarLayout moved outside the bar's window from assistive technologies, which would
/// otherwise still list widgets that cannot be seen or clicked. The layout cannot change its subviews, so the side
/// notices from its own frame that it was moved.
private struct HiddenFromAccessibilityWhenOffscreen: ViewModifier {
    @State private var isOffscreen = false

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { isOffscreen = geometry.frame(in: .global).maxX <= 0 }
                        .onChange(of: geometry.frame(in: .global).maxX <= 0) { _, offscreen in isOffscreen = offscreen }
                }
            )
            .accessibilityHidden(isOffscreen)
    }
}

/// The bar's size, padding and color scheme, shared by both layouts.
private struct BarFrame: ViewModifier {
    @ObservedObject var configManager: ConfigManager
    let theme: ColorScheme?

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.foregroundOutside)
            .frame(height: max(configManager.config.experimental.foreground.resolveHeight(), 1.0))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, configManager.config.experimental.foreground.horizontalPadding)
            .preferredColorScheme(theme)
    }
}

/// Stands for the widgets that do not fit on the bar; clicking it shows them in a popup.
private struct MoreWidgetsWidget<Popup: View>: View {
    let count: Int
    let id: String
    @ViewBuilder let popup: () -> Popup

    @State private var rect: CGRect = .zero

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.barText)
            .experimentalConfiguration()
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.001))
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rect = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, newFrame in rect = newFrame }
                }
            )
            .barWidgetButton(label: "More widgets", value: "\(count) hidden") {
                MenuBarPopup.show(rect: rect, id: id, content: popup)
            }
            .help("Widgets that do not fit on the bar")
    }
}

/// The widgets that do not fit on the bar, each as it is on the bar. They are the popup's glass modules, so the popup
/// adds no glass behind them (glass on glass, which the HIG asks to avoid); clicking one opens its own popup.
private struct MoreWidgetsPopup: View {
    let items: [TomlWidgetItem]
    let view: (TomlWidgetItem) -> AnyView

    @ObservedObject private var configManager = ConfigManager.shared

    var body: some View {
        // Scrolls when there are more widgets than the screen can hold.
        ViewThatFits(in: .vertical) {
            list
            ScrollView { list }
                .scrollIndicators(.automatic)
        }
        .frame(maxHeight: maxHeight)
        .popupProvidesGlassModules()
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Constants.popupModuleSpacing) {
            ForEach(0..<items.count, id: \.self) { index in
                view(items[index])
                    .frame(height: configManager.config.experimental.foreground.resolveHeight())
            }
        }
    }

    /// The popup sits between the bar and the other edge of the screen, with room left for its margins.
    private var maxHeight: CGFloat {
        let screenHeight = NSScreen.barScreen?.visibleFrame.height ?? 800
        return max(screenHeight - configManager.config.experimental.foreground.resolveHeight() - 80, 100)
    }
}
