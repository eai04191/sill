import SwiftUI

// MARK: - Usage Widget

/// Shows the Claude Code and Codex rate limit usage as a logo, a small bar and "10% 2h" per window.
///
/// Config (`[widgets.default.usage]`):
/// - `command`: the command printing the usage JSON, `~/.local/bin/usage-display.sh` by default.
struct UsageWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @StateObject private var usageManager = UsageManager.inUse.instance { UsageManager() }

    @State private var rect: CGRect = .zero

    var body: some View {
        Group {
            if let report = usageManager.report {
                let services = UsageService.allCases.compactMap { service in
                    service.usage(in: report).flatMap { $0.windows.isEmpty ? nil : (service, $0) }
                }
                if !services.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(services, id: \.0) { service, usage in
                            ServiceUsageView(service: service, usage: usage)
                        }
                    }
                    .experimentalConfiguration(cornerRadius: 15)
                    .frame(maxHeight: .infinity)
                    .background(.black.opacity(0.001))
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear { rect = geometry.frame(in: .global) }
                                .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                                    rect = newFrame
                                }
                        }
                    )
                    .barWidgetButton(label: "Usage", value: accessibilitySummary(services)) {
                        MenuBarPopup.show(rect: rect, id: "usage") { UsagePopup() }
                    }
                }
            }
        }
        .onAppear { usageManager.setCommand(configProvider.config["command"]?.stringValue) }
        .onReceive(configProvider.$config) { config in
            usageManager.setCommand(config["command"]?.stringValue)
        }
    }
}

/// Reads each service and its windows, e.g. "Claude Code 16% resets in 1h, 48% resets in 4h".
private func accessibilitySummary(_ services: [(UsageService, ServiceUsage)]) -> String {
    services.map { service, usage in
        let windows = usage.windows.map { window in
            window.reset.map { "\(window.percentText) resets in \($0)" } ?? window.percentText
        }
        return "\(service.displayName) \(windows.joined(separator: ", "))"
    }
    .joined(separator: "; ")
}

/// One service: its logo followed by each window's bar and text.
private struct ServiceUsageView: View {
    let service: UsageService
    let usage: ServiceUsage

    var body: some View {
        HStack(spacing: 6) {
            Image(service.logoName)
                .font(.barText)
            ForEach(Array(usage.windows.enumerated()), id: \.offset) { index, window in
                if index > 0 {
                    Circle()
                        .frame(width: 3, height: 3)
                        .opacity(0.5)
                }
                UsageBar(fraction: window.fraction)
                    .frame(width: 28, height: 4)
                Text(window.reset.map { "\(window.percentText) \($0)" } ?? window.percentText)
                    .font(.barText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// A capsule progress bar drawn with the foreground color on a translucent track.
struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().opacity(0.25)
                Capsule()
                    .frame(width: max(geometry.size.width * fraction, geometry.size.height))
                    .animation(.easeOut(duration: 0.24), value: fraction)
            }
        }
    }
}
