import SwiftUI

/// Details of the rate limit usage: each window's progress and reset time, with a link to the usage page.
struct UsagePopup: View {
    @StateObject private var usageManager = UsageManager.inUse.instance { UsageManager() }

    var body: some View {
        modules
    }

    /// Like the Control Center, each service is its own glass module instead of sharing one glass panel.
    private var modules: some View {
        VStack(spacing: Constants.popupModuleSpacing) {
            ForEach(sections, id: \.0) { service, usage in
                ServiceUsageSection(service: service, usage: usage)
                    .frame(width: 260, alignment: .leading)
                    .padding(Constants.popupPadding)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
            }
            if sections.isEmpty {
                unavailable
                    .frame(width: 260, alignment: .leading)
                    .padding(Constants.popupPadding)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
            }
        }
    }

    private var sections: [(UsageService, ServiceUsage)] {
        guard let report = usageManager.report else { return [] }
        return UsageService.allCases.compactMap { service in
            service.usage(in: report).flatMap { $0.windows.isEmpty ? nil : (service, $0) }
        }
    }

    private var unavailable: some View {
        Text("Usage is not available")
            .foregroundStyle(.secondary)
    }
}

private struct ServiceUsageSection: View {
    let service: UsageService
    let usage: ServiceUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(service.logoName)
                    .font(.popupHeading)
                Text(service.displayName)
                    .font(.popupHeading)
                Spacer()
                Link(destination: service.usagePageURL) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.headline)
                        .minimumHitArea()
                }
                .buttonStyle(.plain)
                .help("Open the usage page")
                // The symbol alone was read as "arrow up right square".
                .accessibilityLabel("Open usage page for \(service.displayName)")
            }
            ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, window in
                VStack(alignment: .leading, spacing: 4) {
                    // The native linear ProgressView skipped drawing its track for some values, so use the bar's own style.
                    UsageBar(fraction: window.fraction)
                        .frame(height: 6)
                    HStack {
                        Text(window.label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(window.percentText)
                            .monospacedDigit()
                        if let reset = window.reset {
                            // The reset time is formatted by the usage command, e.g. "2h", and shown as it is.
                            Text("· resets in \(reset)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }
}
