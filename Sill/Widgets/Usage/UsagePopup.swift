import SwiftUI

/// Details of the rate limit usage: each window's progress, reset time and pace, the plan, extra usage and resets,
/// with links to the usage and status pages.
struct UsagePopup: View {
    @StateObject private var usageManager = UsageManager.inUse.instance { UsageManager() }

    var body: some View {
        TimelineView(.everyMinute) { context in
            modules(now: context.date)
        }
    }

    /// Like the Control Center, each service is its own glass module instead of sharing one glass panel.
    private func modules(now: Date) -> some View {
        VStack(spacing: Constants.popupModuleSpacing) {
            ForEach(services) { report in
                ServiceUsageSection(report: report, now: now)
                    .frame(width: 260, alignment: .leading)
                    .padding(Constants.popupPadding)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
            }
            if services.isEmpty {
                unavailable
                    .frame(width: 260, alignment: .leading)
                    .padding(Constants.popupPadding)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Constants.popupCornerRadius))
            }
        }
    }

    private var services: [ServiceReport] { usageManager.report?.services ?? [] }

    @ViewBuilder
    private var unavailable: some View {
        if usageManager.isCodexBarMissing {
            VStack(alignment: .leading, spacing: 4) {
                Text("CodexBar is not installed")
                Text("Install it with `brew install --cask codexbar`, open it once to sign in, and quit it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Usage is not available")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ServiceUsageSection: View {
    let report: ServiceReport
    let now: Date

    private var usage: ServiceUsage { report.usage }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(Array(report.windows.enumerated()), id: \.offset) { _, item in
                WindowRow(label: item.window.label, window: item.window, pace: item.pace, now: now)
            }
            ForEach(usage.extraRateWindows ?? [], id: \.id) { scoped in
                // CodexBar names the scope in English only, e.g. "Fable only".
                WindowRow(label: "\(scoped.window.label) · \(scoped.title)", window: scoped.window, pace: nil, now: now)
            }
            if !infoRows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(infoRows.enumerated()), id: \.offset) { _, row in
                        InfoRow(label: row.label, value: row.value, secondaryValue: row.secondaryValue)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(report.service.logoName)
                .font(.popupHeading)
            VStack(alignment: .leading, spacing: 0) {
                Text(report.service.displayName)
                    .font(.popupHeading)
                if let plan = usage.loginMethod, !plan.isEmpty {
                    Text(plan)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(-1)
            Spacer(minLength: 0)
            Link(destination: report.service.statusPageURL) {
                Image(systemName: "waveform.path.ecg")
                    .font(.headline)
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
            .help("Open the status page")
            .accessibilityLabel("Open status page for \(report.service.displayName)")
            Link(destination: report.service.usagePageURL) {
                Image(systemName: "arrow.up.right.square")
                    .font(.headline)
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
            .help("Open the usage page")
            // The symbol alone was read as "arrow up right square".
            .accessibilityLabel("Open usage page for \(report.service.displayName)")
        }
    }

    /// Extra usage, rate limit resets and the service-specific details, one label and value each.
    private var infoRows: [UsageDetailSection.Row] {
        var rows: [UsageDetailSection.Row] = []
        if let extra = usage.providerCost, extra.isInUse {
            rows.append(
                .init(
                    label: String(localized: "Extra usage", comment: "Paid usage beyond the plan's rate limits."),
                    value: extra.text, secondaryValue: nil))
        }
        if let credits = report.resetCredits, credits.available > 0 {
            rows.append(
                .init(
                    label: String(localized: "Rate limit resets", comment: "Free resets of the rate limits the service granted."),
                    value: String(
                        localized: "\(credits.available) available",
                        comment: "How many free rate limit resets can be used, e.g. \"3 available\"."),
                    secondaryValue: credits.nextExpiresAt.map {
                        String(
                            localized: "Next expires \($0.formatted(.dateTime.month().day()))",
                            comment: "The date the first free rate limit reset expires, e.g. \"Next expires Oct 22\".")
                    }))
        }
        // Prepared by CodexBar for display, in English only.
        rows += (usage.details ?? []).flatMap { $0.rows ?? [] }
        return rows
    }
}

/// A window's bar, with its name, usage and reset time below, and its pace when the service reports it.
private struct WindowRow: View {
    let label: String
    let window: UsageWindow
    let pace: UsagePace?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The native linear ProgressView skipped drawing its track for some values, so use the bar's own style.
            UsageBar(fraction: window.fraction)
                .frame(height: 6)
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
                Spacer(minLength: 4)
                Text(window.percentText)
                    .monospacedDigit()
                if let reset = window.resetText(now: now) {
                    Text("· resets in \(reset)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let pace {
                Text(pace.text)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: 11))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    let secondaryValue: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value)
                    .monospacedDigit()
                    .lineLimit(1)
                if let secondaryValue {
                    Text(secondaryValue)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: 11))
    }
}
