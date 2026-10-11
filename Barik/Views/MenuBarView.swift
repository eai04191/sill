import SwiftUI

struct MenuBarView: View {
    @ObservedObject var configManager = ConfigManager.shared

    var body: some View {
        let usesGlass = configManager.config.usesLiquidGlass
        // With the system theme, glass widgets are dark glass with white text like the glass popups and the Control
        // Center. The HIG has small glass elements adapt to the content behind them, but only system components do
        // that; custom glass keeps the window's appearance whatever is behind it. The window appearance decides how
        // the glass is drawn, so it is set with preferredColorScheme. After turning Liquid Glass off while running,
        // the bar keeps the dark appearance until Barik restarts, because preferredColorScheme(nil) does not reset
        // the window appearance; the material bar draws its own colors, so this is left as is.
        let theme: ColorScheme? =
            switch configManager.config.rootToml.theme {
            case "dark":
                .dark
            case "light":
                .light
            default:
                usesGlass ? .dark : .none
            }

        let items = configManager.config.rootToml.widgets.displayed

        let showsBanner = !items.contains(where: { $0.id == "system-banner" })

        let spacing = configManager.config.experimental.foreground.spacing

        if let sections = CenteredSections(items) {
            // Spacers split the free width between the sides, which only centers the middle widgets when both sides
            // are equally wide. Place them at the center of the whole bar (including the banner) instead, and keep
            // the sides to the space next to them. Widgets that do not fit are left out, nearest to the center first,
            // like status items in the macOS menu bar; clipping does not work because glass and the content on it
            // are drawn outside the clip.
            CenteredBarLayout(spacing: spacing) {
                LiquidGlassContainer(enabled: usesGlass, spacing: spacing) {
                    fittingRow(sections.leading, dropping: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LiquidGlassContainer(enabled: usesGlass, spacing: spacing) {
                    row(sections.centered)
                }
                LiquidGlassContainer(enabled: usesGlass, spacing: spacing) {
                    HStack(spacing: 0) {
                        fittingRow(sections.trailing, dropping: .leading)
                        if showsBanner {
                            SystemBannerWidget(withLeftPadding: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .modifier(BarFrame(configManager: configManager, theme: theme))
        } else {
            LiquidGlassContainer(enabled: usesGlass, spacing: spacing) {
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

    /// The widgets that fit the offered width: all of them, or fewer by leaving out widgets from the given edge. The
    /// left-out widgets are kept in a "more" widget on that edge, which shows them in a popup. When even the "more"
    /// widget does not fit, ViewThatFits still shows it, and CenteredBarLayout moves the side away.
    private func fittingRow(_ items: [TomlWidgetItem], dropping edge: HorizontalEdge) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach(0...items.count, id: \.self) { dropped in
                let shown = edge == .trailing ? Array(items.prefix(items.count - dropped)) : Array(items.suffix(items.count - dropped))
                let hidden = edge == .trailing ? Array(items.suffix(dropped)) : Array(items.prefix(dropped))
                HStack(spacing: configManager.config.experimental.foreground.spacing) {
                    if edge == .leading, !hidden.isEmpty { moreWidget(hidden) }
                    row(shown)
                    if edge == .trailing, !hidden.isEmpty { moreWidget(hidden) }
                }
            }
        }
    }

    private func moreWidget(_ items: [TomlWidgetItem]) -> some View {
        MoreWidgetsWidget(count: items.count) {
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
            TimeWidget(calendarManager: CalendarManager(configProvider: config))
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

/// Places three views on the bar: the second at the center of the whole width, the first leading and the third
/// trailing, each limited to the space between the bar edge and the centered view so they never overlap it.
private struct CenteredBarLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let centered = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: bounds.height))
        let side = max(0, (bounds.width - centered.width) / 2 - spacing)
        let sideProposal = ProposedViewSize(width: side, height: bounds.height)
        subviews[1].place(
            at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(centered))
        subviews[0].place(
            at: fits(subviews[0], in: sideProposal) ? CGPoint(x: bounds.minX, y: bounds.midY) : offscreen,
            anchor: .leading, proposal: sideProposal)
        subviews[2].place(
            at: fits(subviews[2], in: sideProposal) ? CGPoint(x: bounds.maxX, y: bounds.midY) : offscreen,
            anchor: .trailing, proposal: sideProposal)
    }

    /// Whether a side is no wider than its space. ViewThatFits shows its last candidate even when it does not fit,
    /// and widgets with fixed-size text do not shrink, so a side can still be wider than offered.
    private func fits(_ subview: LayoutSubview, in proposal: ProposedViewSize) -> Bool {
        subview.sizeThatFits(proposal).width <= (proposal.width ?? 0) + 0.5
    }

    /// Where a side that does not fit is placed so it is not drawn over the centered widgets. A layout cannot remove
    /// a subview, and clipping does not hide Liquid Glass, so it is moved outside the bar's window instead.
    private let offscreen = CGPoint(x: -100_000, y: 0)
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
            .background(.black.opacity(0.001))
            .preferredColorScheme(theme)
    }
}

/// Stands for the widgets that do not fit on the bar; clicking it shows them in a popup.
private struct MoreWidgetsWidget<Popup: View>: View {
    let count: Int
    @ViewBuilder let popup: () -> Popup

    @State private var rect: CGRect = .zero

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.barText)
            .experimentalConfiguration(cornerRadius: 15)
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.001))
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rect = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, newFrame in rect = newFrame }
                }
            )
            .barButton(label: "More widgets", value: "\(count) hidden") {
                MenuBarPopup.show(rect: rect, id: "more-widgets", content: popup)
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
        VStack(alignment: .leading, spacing: Constants.popupModuleSpacing) {
            ForEach(0..<items.count, id: \.self) { index in
                view(items[index])
                    .frame(height: configManager.config.experimental.foreground.resolveHeight())
            }
        }
        .padding(configManager.config.usesLiquidGlass ? 0 : 20)
        .applying(configManager.config.usesLiquidGlass) { $0.popupProvidesGlassModules() }
    }
}
