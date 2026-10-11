import Combine
import Foundation

// MARK: - Usage Models

/// One rate limit window, e.g. the 5-hour or the weekly limit.
struct UsageWindow: Decodable, Equatable {
    /// Used percentage between 0 and 100.
    let pct: Double
    /// Time until the window resets, already formatted (e.g. "2h", "4d").
    let reset: String?
    /// Length of the window in minutes (e.g. 300 for the 5-hour limit), when the command reports it.
    let mins: Int?

    /// The window's name from its length. Services do not agree on which limit comes first (Codex can report only a
    /// weekly window as primary), so without a length the window is not named by its position.
    var label: String {
        switch mins {
        case 10080: return "Weekly"
        case let mins? where mins > 0 && mins % 1440 == 0: return "\(mins / 1440)-day"
        case let mins? where mins > 0 && mins % 60 == 0: return "\(mins / 60)-hour"
        case let mins? where mins > 0: return "\(mins)-minute"
        default: return "Usage"
        }
    }

    var fraction: Double { min(max(pct / 100, 0), 1) }
    var percentText: String { "\(Int(pct.rounded()))%" }
}

/// The usage of one service, with its primary (shorter) and secondary (longer) windows.
struct ServiceUsage: Decodable, Equatable {
    let primary: UsageWindow?
    let secondary: UsageWindow?

    var windows: [UsageWindow] { [primary, secondary].compactMap { $0 } }
}

/// The JSON printed by the usage command.
struct UsageReport: Decodable, Equatable {
    let claude: ServiceUsage?
    let codex: ServiceUsage?
}

/// The services shown by the usage widget.
enum UsageService: String, CaseIterable, Identifiable {
    case claude, codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var logoName: String {
        switch self {
        case .claude: "ClaudeLogo"
        case .codex: "CodexLogo"
        }
    }

    var usagePageURL: URL {
        switch self {
        case .claude: URL(string: "https://claude.ai/settings/usage")!
        case .codex: URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage")!
        }
    }

    func usage(in report: UsageReport) -> ServiceUsage? {
        switch self {
        case .claude: report.claude
        case .codex: report.codex
        }
    }
}

// MARK: - Usage Manager

/// Periodically runs the usage command and publishes its report.
///
/// The command (by default `~/.local/bin/usage-display.sh`) is expected to print
/// `{"claude": {"primary": {"pct": 10, "reset": "2h"}, "secondary": ...}, "codex": ...}`.
/// Fetching and caching the usage is left to that command, so this only reads its output.
final class UsageManager: ObservableObject {
    static let shared = UsageManager()
    static let defaultCommand = "~/.local/bin/usage-display.sh"

    @Published private(set) var report: UsageReport?

    private var command = UsageManager.defaultCommand
    private var timer: AnyCancellable?
    /// Set while the command runs, so a slow command is not started again on every tick.
    private var isRunning = false
    /// A command that hangs is stopped after this many seconds.
    private static let timeout: TimeInterval = 10

    private init() {
        timer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    /// Changes the command from the widget config; an empty or missing value keeps the default.
    func setCommand(_ newCommand: String?) {
        let resolved = (newCommand?.isEmpty == false ? newCommand : nil) ?? Self.defaultCommand
        guard resolved != command else { return }
        command = resolved
        refresh()
    }

    private func refresh() {
        guard !isRunning else { return }
        isRunning = true
        let path = (command as NSString).expandingTildeInPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let report = Self.run(path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                if self.report != report {
                    self.report = report
                }
            }
        }
    }

    /// Returns nil when the command is missing, fails, or prints something that is not a usage report,
    /// which hides the widget instead of showing stale numbers.
    private static func run(_ path: String) -> UsageReport? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Terminating the command closes its end of the output and ends the read below. A child process of the command
        // that still holds the output open keeps the read waiting until it exits; refresh() still never overlaps runs.
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { process.terminate() }
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(UsageReport.self, from: output)
    }
}
