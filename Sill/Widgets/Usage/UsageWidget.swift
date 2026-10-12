import SwiftUI

// MARK: - Usage Widget

/// Shows the Claude Code and Codex rate limit usage as a logo, a small bar and "10% 2h" per window, from CodexBar
/// (`brew install --cask codexbar`).
struct UsageWidget: View {
    @StateObject private var usageManager = UsageManager.inUse.instance { UsageManager() }

    @State private var rect: CGRect = .zero

    var body: some View {
        if let report = usageManager.report, !report.services.isEmpty {
            // The time until each window resets is counted down between reads of the server.
            TimelineView(.everyMinute) { context in
                HStack(spacing: 14) {
                    ForEach(report.services) { service in
                        ServiceUsageView(report: service, now: context.date)
                    }
                }
                .popupButton(rect: $rect, value: accessibilitySummary(report.services, now: context.date))
            }
        } else if usageManager.isCodexBarMissing {
            // Says that CodexBar is missing rather than hiding, as a widget that never appears gives no hint why.
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.barText)
                .popupButton(
                    rect: $rect,
                    value: String(localized: "CodexBar is not installed", comment: "VoiceOver: the usage widget without CodexBar."))
        }
    }
}

extension View {
    /// Makes the widget's content a bar button that opens the usage popup below it.
    fileprivate func popupButton(rect: Binding<CGRect>, value: String) -> some View {
        experimentalConfiguration()
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.001))
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rect.wrappedValue = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                            rect.wrappedValue = newFrame
                        }
                }
            )
            .barWidgetButton(label: "Usage", value: value) {
                MenuBarPopup.show(rect: rect.wrappedValue, id: "usage", providesGlassModules: true) { UsagePopup() }
            }
    }
}

/// Reads each service and its windows, e.g. "Claude Code 16% resets in 1h, 48% resets in 4h".
private func accessibilitySummary(_ services: [ServiceReport], now: Date) -> String {
    services.map { report in
        let windows = report.windows.map { window, _ in
            window.resetText(now: now).map {
                String(
                    localized: "\(window.percentText) resets in \($0)",
                    comment: "VoiceOver: a rate limit window's usage and the time until it resets, e.g. \"16% resets in 1h\".")
            } ?? window.percentText
        }
        return "\(report.service.displayName) \(windows.joined(separator: ", "))"
    }
    .joined(separator: "; ")
}

/// One service: its logo followed by each window's bar and text.
private struct ServiceUsageView: View {
    let report: ServiceReport
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Image(report.service.logoName)
                .font(.barText)
            ForEach(Array(report.windows.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Circle()
                        .frame(width: 3, height: 3)
                        .opacity(0.5)
                }
                UsageBar(fraction: item.window.fraction)
                    .frame(width: 28, height: 4)
                Text(item.window.resetText(now: now).map { "\(item.window.percentText) \($0)" } ?? item.window.percentText)
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
