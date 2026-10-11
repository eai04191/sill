import SwiftUI

struct MenuBarView: View {
    @ObservedObject var configManager = ConfigManager.shared

    var body: some View {
        let theme: ColorScheme? =
            switch configManager.config.rootToml.theme {
            case "dark":
                .dark
            case "light":
                .light
            default:
                .none
            }

        let items = configManager.config.rootToml.widgets.displayed

        HStack(spacing: 0) {
            LiquidGlassContainer(
                enabled: configManager.config.usesLiquidGlass,
                spacing: configManager.config.experimental.foreground.spacing
            ) {
                if let sections = CenteredSections(items) {
                    // Spacers split the free width between the sides, which only centers the middle widgets when
                    // both sides are equally wide. Overlay them instead so they stay at the center of the bar.
                    ZStack {
                        HStack(spacing: 0) {
                            row(sections.leading)
                            Spacer(minLength: 0)
                            row(sections.trailing)
                        }
                        row(sections.centered)
                    }
                } else {
                    row(items)
                }
            }

            if !items.contains(where: { $0.id == "system-banner" }) {
                SystemBannerWidget(withLeftPadding: true)
            }
        }
        .foregroundStyle(Color.foregroundOutside)
        .frame(height: max(configManager.config.experimental.foreground.resolveHeight(), 1.0))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, configManager.config.experimental.foreground.horizontalPadding)
        .background(.black.opacity(0.001))
        .preferredColorScheme(theme)
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
