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
    /// Formatted rather than converted to Int, which traps for a value beyond Int's range.
    var percentText: String { "\(pct.formatted(.number.precision(.fractionLength(0)).grouping(.never)))%" }
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
        case .claude: "claude.logo"
        case .codex: "openai.logo"
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
    /// One manager for the usage widgets on the bar and their popup, released with its polling once none shows it.
    static let inUse = SharedWhileInUse<UsageManager>()
    static let defaultCommand = "~/.local/bin/usage-display.sh"

    @Published private(set) var report: UsageReport?

    private var command = UsageManager.defaultCommand
    private var timer: AnyCancellable?
    /// Set while the command runs, so a slow command is not started again on every tick.
    private var isRunning = false
    /// A command that hangs is stopped after this many seconds.
    private static let timeout: TimeInterval = 10

    init() {
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
        let reader = OutputReader(pipe.fileHandleForReading)
        do {
            try process.run()
        } catch {
            _ = reader.finish()
            return nil
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()
        let output = reader.finish()
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(UsageReport.self, from: output)
    }
}

/// Reads a command's output as it arrives, and takes what was printed once the command exits.
///
/// Reading the output to its end would wait for every process holding it open, including a child process the command
/// left running, which terminating the command after its timeout does not reach; the run then never ended.
private final class OutputReader {
    private let queue = DispatchQueue(label: "UsageManager.OutputReader")
    private let fileDescriptor: Int32
    private let source: DispatchSourceRead
    private var data = Data()

    init(_ handle: FileHandle) {
        fileDescriptor = handle.fileDescriptor
        _ = fcntl(fileDescriptor, F_SETFL, fcntl(fileDescriptor, F_GETFL) | O_NONBLOCK)
        source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.read() }
        // The handle closes the descriptor when released, which must wait until the source no longer reads it.
        source.setCancelHandler { _ = handle }
        source.resume()
    }

    /// Reads everything available without waiting; stops at the end of the output.
    private func read() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fileDescriptor, &buffer, buffer.count)
            guard count > 0 else {
                if count == 0 { source.cancel() }
                return
            }
            data.append(buffer, count: count)
        }
    }

    /// Reads what is left without waiting, stops reading and returns the output.
    func finish() -> Data {
        queue.sync {
            if !source.isCancelled {
                read()
                source.cancel()
            }
            return data
        }
    }
}
