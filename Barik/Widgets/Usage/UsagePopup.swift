import SwiftUI

/// Details of the rate limit usage: each window's progress and reset time, with a link to the usage page.
struct UsagePopup: View {
    @ObservedObject private var usageManager = UsageManager.shared
    @ObservedObject private var configManager = ConfigManager.shared

    var body: some View {
        modules.popupFollowsSystemAppearance()
    }

    @ViewBuilder
    private var modules: some View {
        if configManager.config.usesLiquidGlass {
            // Like the Control Center, each service is its own glass module instead of sharing one glass panel.
            VStack(spacing: Constants.popupModuleSpacing) {
                ForEach(sections, id: \.0) { service, usage in
                    ServiceUsageSection(service: service, usage: usage)
                        .frame(width: 260, alignment: .leading)
                        .padding(20)
                        .liquidGlassBackground(true, in: RoundedRectangle(cornerRadius: Constants.popupCornerRadius)) {
                            EmptyView()
                        }
                }
                if sections.isEmpty {
                    unavailable
                        .frame(width: 260, alignment: .leading)
                        .padding(20)
                        .liquidGlassBackground(true, in: RoundedRectangle(cornerRadius: Constants.popupCornerRadius)) {
                            EmptyView()
                        }
                }
            }
            .popupProvidesGlassModules()
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections, id: \.0) { service, usage in
                    ServiceUsageSection(service: service, usage: usage)
                }
                if sections.isEmpty {
                    unavailable
                }
            }
            .frame(width: 260, alignment: .leading)
            .padding(24)
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
                .help("Open the usage page")
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
