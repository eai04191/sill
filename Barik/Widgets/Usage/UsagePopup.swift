import SwiftUI

/// Details of the rate limit usage: each window's progress and reset time, with a link to the usage page.
struct UsagePopup: View {
    @ObservedObject private var usageManager = UsageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let report = usageManager.report {
                ForEach(UsageService.allCases) { service in
                    if let usage = service.usage(in: report), !usage.windows.isEmpty {
                        ServiceUsageSection(service: service, usage: usage)
                    }
                }
            } else {
                Text("Usage is not available")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 260, alignment: .leading)
        .padding(24)
    }
}

private struct ServiceUsageSection: View {
    let service: UsageService
    let usage: ServiceUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(service.logoName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text(service.displayName)
                    .font(.headline)
                Spacer()
                Link(destination: service.usagePageURL) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                // The popup panel becomes key when shown, which otherwise draws a focus ring on the first link.
                .focusEffectDisabled()
                .help("Open the usage page")
            }
            ForEach(Array(usage.windows.enumerated()), id: \.offset) { index, window in
                VStack(alignment: .leading, spacing: 4) {
                    // The native linear ProgressView skipped drawing its track for some values, so use the bar's own style.
                    UsageBar(fraction: window.fraction)
                        .frame(height: 6)
                    HStack {
                        Text(label(forWindowAt: index))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(window.percentText)
                            .monospacedDigit()
                        if let reset = window.reset {
                            Text("· resets in \(reset)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 11))
                }
            }
        }
        .foregroundStyle(.white)
    }

    /// With two windows the first is the session (5-hour) limit and the second the weekly one;
    /// a single window is not labeled by length because services differ in which one they report.
    private func label(forWindowAt index: Int) -> String {
        guard usage.windows.count > 1 else { return "Usage" }
        return index == 0 ? "Session" : "Weekly"
    }
}
