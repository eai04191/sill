import AppKit
import Combine
import Foundation
import os

// MARK: - Usage Models

/// One rate limit window, e.g. the 5-hour or the weekly limit, as CodexBar reports it.
struct UsageWindow: Decodable, Equatable {
    /// Used percentage between 0 and 100.
    let usedPercent: Double
    /// Length of the window in minutes (e.g. 300 for the 5-hour limit), when the service reports it.
    let windowMinutes: Int?
    let resetsAt: Date?

    /// The window's name from its length. Services do not agree on which limit comes first (Codex can report only a
    /// weekly window as primary), so without a length the window is not named by its position.
    var label: String {
        switch windowMinutes {
        case 10080: return String(localized: "Weekly", comment: "The weekly rate limit window.")
        case let mins? where mins > 0 && mins % 1440 == 0:
            return String(localized: "\(mins / 1440)-day", comment: "A rate limit window of this many days.")
        case let mins? where mins > 0 && mins % 60 == 0:
            return String(localized: "\(mins / 60)-hour", comment: "A rate limit window of this many hours.")
        case let mins? where mins > 0:
            return String(localized: "\(mins)-minute", comment: "A rate limit window of this many minutes.")
        default: return String(localized: "Usage", comment: "A rate limit window of unknown length.")
        }
    }

    var fraction: Double { min(max(usedPercent / 100, 0), 1) }
    /// Formatted rather than converted to Int, which traps for a value beyond Int's range.
    var percentText: String { "\(usedPercent.formatted(.number.precision(.fractionLength(0)).grouping(.never)))%" }

    /// Time until the window resets, e.g. "2h", or nil once it has passed or when the service does not report it.
    func resetText(now: Date) -> String? {
        guard let resetsAt, resetsAt > now else { return nil }
        return compactDuration(resetsAt.timeIntervalSince(now))
    }
}

/// A window limited to part of a service, e.g. a weekly limit for one model.
struct ScopedUsageWindow: Decodable, Equatable {
    let id: String
    /// The scope as CodexBar names it, e.g. "Fable only"; it comes in English only.
    let title: String
    let window: UsageWindow
}

/// How the use of a window compares with an even use of it up to now.
struct UsagePace: Decodable, Equatable {
    /// Percentage points used beyond (positive) or short of (negative) an even use.
    let deltaPercent: Double
    let willLastToReset: Bool
    /// Seconds until the window runs out at the current pace, when it runs out before resetting.
    let etaSeconds: Double?

    var text: String {
        let delta = abs(deltaPercent).formatted(.number.precision(.fractionLength(0)).grouping(.never))
        let balance =
            deltaPercent < 0
            ? String(localized: "\(delta)% in reserve", comment: "Usage below an even pace, e.g. \"72% in reserve\".")
            : String(localized: "\(delta)% in deficit", comment: "Usage above an even pace, e.g. \"3% in deficit\".")
        if willLastToReset {
            return String(
                localized: "\(balance) · lasts until reset",
                comment: "The pace of a rate limit window that lasts until it resets, e.g. \"72% in reserve · lasts until reset\".")
        }
        if let etaSeconds {
            return String(
                localized: "\(balance) · runs out in \(compactDuration(etaSeconds))",
                comment: "The pace of a rate limit window that runs out before it resets, e.g. \"3% in deficit · runs out in 4d\".")
        }
        return balance
    }
}

struct WindowPaces: Decodable, Equatable {
    let primary: UsagePace?
    let secondary: UsagePace?
    let tertiary: UsagePace?
}

/// Paid usage beyond the plan's limits, e.g. Claude's extra usage with its monthly cap.
struct ExtraUsage: Decodable, Equatable {
    let used: Double
    let limit: Double
    /// An ISO 4217 code such as "USD", or "Credits" for Codex.
    let currencyCode: String

    /// Codex reports 0 of 0 credits for an account without extra usage, which is not worth a row.
    var isInUse: Bool { limit > 0 || used > 0 }

    var text: String { "\(format(used)) / \(format(limit))" }

    private func format(_ amount: Double) -> String {
        if Locale.Currency.isoCurrencies.contains(where: { $0.identifier == currencyCode }) {
            return amount.formatted(.currency(code: currencyCode))
        }
        return "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(currencyCode)"
    }
}

/// Free resets of the rate limits that the service granted, which Codex reports apart from its details.
struct ResetCredits: Decodable, Equatable {
    let available: Int
    let nextExpiresAt: Date?
}

/// A section of service-specific information, which CodexBar prepares for display and sends in English only.
struct UsageDetailSection: Decodable, Equatable {
    struct Row: Decodable, Equatable {
        let label: String
        let value: String
        let secondaryValue: String?
    }

    let title: String?
    let rows: [Row]?
}

/// The usage of one service, CodexBar's `usage` object.
struct ServiceUsage: Decodable, Equatable {
    let primary: UsageWindow?
    let secondary: UsageWindow?
    let tertiary: UsageWindow?
    let extraRateWindows: [ScopedUsageWindow]?
    /// The plan, e.g. "Claude Max 20x".
    let loginMethod: String?
    let providerCost: ExtraUsage?
    let details: [UsageDetailSection]?
}

/// One service's entry in the array `GET /usage` returns.
private struct ProviderEntry: Decodable {
    struct ProviderError: Decodable {
        let message: String?
    }

    let provider: String
    let usage: ServiceUsage?
    let pace: WindowPaces?
    let resetCredits: ResetCredits?
    let error: ProviderError?
}

/// What the widget and its popup show of one service.
struct ServiceReport: Equatable, Identifiable {
    let service: UsageService
    let usage: ServiceUsage
    let pace: WindowPaces?
    let resetCredits: ResetCredits?

    var id: UsageService { service }

    /// The service's own windows with their pace, shortest first as the service orders them.
    var windows: [(window: UsageWindow, pace: UsagePace?)] {
        [(usage.primary, pace?.primary), (usage.secondary, pace?.secondary), (usage.tertiary, pace?.tertiary)]
            .compactMap { window, pace in window.map { ($0, pace) } }
    }
}

/// The services CodexBar reported usage for, in the widget's order.
struct UsageReport: Equatable {
    let services: [ServiceReport]

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
        }
        return decoder
    }()

    /// Reads the response of `GET /usage`. A service that failed is left out and its error logged; CodexBar keeps
    /// the last good usage of a service whose fetch failed only for a while, so such an error is not a passing one.
    init(from data: Data) throws {
        let entries = try Self.decoder.decode([ProviderEntry].self, from: data)
        for entry in entries where entry.error != nil {
            Logger.usage.error(
                "CodexBar could not get the usage of \(entry.provider, privacy: .public): \(entry.error?.message ?? "no message", privacy: .public)"
            )
        }
        services = UsageService.allCases.compactMap { service in
            guard let entry = entries.first(where: { $0.provider == service.rawValue }), let usage = entry.usage
            else { return nil }
            let report = ServiceReport(service: service, usage: usage, pace: entry.pace, resetCredits: entry.resetCredits)
            return report.windows.isEmpty ? nil : report
        }
    }
}

/// The services shown by the usage widget, named by their CodexBar provider IDs.
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

    var statusPageURL: URL {
        switch self {
        case .claude: URL(string: "https://status.claude.com/")!
        case .codex: URL(string: "https://status.openai.com/")!
        }
    }
}

/// A duration in its largest unit, rounded down, e.g. "2h" or "4d" ("2時間", "4日" in Japanese).
func compactDuration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(
        .units(
            allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 1,
            fractionalPart: .hide(rounded: .down)))
}

// MARK: - Usage Manager

/// Reads the usage from the CodexBar server this manager runs, and publishes it.
final class UsageManager: ObservableObject {
    /// One manager for the usage widgets on the bar and their popup, released with its server once none shows it.
    static let inUse = SharedWhileInUse<UsageManager>()

    @Published private(set) var report: UsageReport?
    /// Set while CodexBar's CLI is not installed, which the widget says instead of hiding.
    @Published private(set) var isCodexBarMissing = false

    private var server: CodexBarServer?
    private var usageURL: URL?
    private var task: URLSessionDataTask?
    private var timer: AnyCancellable?
    private var terminateObserver: NSObjectProtocol?
    /// Connections refused since the server started, which it does until it listens.
    private var refusedConnections = 0

    /// The server answers from its cache, which decides how often the services are asked (see
    /// `CodexBarServer.refreshInterval`), so reading it often costs little and only bounds how late a new value shows.
    private static let pollInterval: TimeInterval = 60
    /// The first request after the server starts waits for the services, which took up to about 6 seconds; the
    /// server gives up on a request after 30 seconds by default.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 40
        return URLSession(configuration: configuration)
    }()
    /// The server listens within about a second of starting; it is asked once a second until then.
    private static let maxRefusedConnections = 10

    init() {
        server = CodexBarServer(
            onChange: { [weak self] url in self?.serverDidChange(url) },
            onMissingChange: { [weak self] missing in self?.isCodexBarMissing = missing })
        timer = Timer.publish(every: Self.pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        // Ends the server with Sill, as a child process otherwise outlives it.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.server?.stop()
        }
        server?.start()
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
        task?.cancel()
        server?.stop()
    }

    private func serverDidChange(_ url: URL?) {
        usageURL = url
        task?.cancel()
        task = nil
        refusedConnections = 0
        if url == nil {
            report = nil
        } else {
            refresh()
        }
    }

    private func refresh() {
        guard let url = usageURL, task == nil else { return }
        let task = Self.session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, url == self.usageURL else { return }
                self.task = nil
                self.receive(data: data, response: response, error: error)
            }
        }
        self.task = task
        task.resume()
    }

    private func receive(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error as? URLError, error.code == .cannotConnectToHost,
            refusedConnections < Self.maxRefusedConnections
        {
            refusedConnections += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
            return
        }
        let report: UsageReport?
        if let error {
            Logger.usage.error("Could not read codexbar serve: \(String(describing: error), privacy: .public)")
            report = nil
        } else if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            Logger.usage.error("codexbar serve answered with status \(status, privacy: .public)")
            report = nil
        } else {
            do {
                report = try UsageReport(from: data ?? Data())
            } catch {
                Logger.usage.error(
                    "codexbar serve sent usage that could not be read (\(data?.count ?? 0, privacy: .public) bytes): \(String(describing: error), privacy: .public)"
                )
                report = nil
            }
        }
        if self.report != report {
            self.report = report
        }
    }
}

/// Stops a command that hangs, for codexbar serve, media-control and AeroSpace.
enum ProcessStopper {
    /// Seconds a terminated process has to exit before it is killed.
    static let killGracePeriod: TimeInterval = 2

    /// Terminates the process if it still runs after `delay` seconds, and kills it if it still runs
    /// `killGracePeriod` seconds later, as a process that ignores SIGTERM would otherwise be waited for forever.
    static func stop(_ process: Process, after delay: TimeInterval = 0) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            guard process.isRunning else { return }
            let name = process.executableURL?.lastPathComponent ?? "unknown"
            Logger.commands.notice("Terminating \(name, privacy: .public), pid \(process.processIdentifier, privacy: .public)")
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + killGracePeriod) {
                guard process.isRunning else { return }
                Logger.commands.error("Killing \(name, privacy: .public), pid \(process.processIdentifier, privacy: .public), which ignored SIGTERM")
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

/// Reads a command's output as it arrives, and takes what was printed once the command exits.
///
/// Reading the output to its end would wait for every process holding it open, including a child process the command
/// left running, which terminating the command after its timeout does not reach; the run then never ended.
final class OutputReader {
    private let queue = DispatchQueue(label: "OutputReader")
    private let fileDescriptor: Int32
    private let source: DispatchSourceRead
    private let limit: Int?
    private let onLimitExceeded: () -> Void
    private var data = Data()
    private var _exceededLimit = false

    /// - Parameters:
    ///   - limit: The most bytes kept. Reading stops at the first byte beyond it and `onLimitExceeded` is called once,
    ///     where the caller stops the command, which could otherwise fill memory with its output.
    init(_ handle: FileHandle, limit: Int? = nil, onLimitExceeded: @escaping () -> Void = {}) {
        fileDescriptor = handle.fileDescriptor
        self.limit = limit
        self.onLimitExceeded = onLimitExceeded
        _ = fcntl(fileDescriptor, F_SETFL, fcntl(fileDescriptor, F_GETFL) | O_NONBLOCK)
        source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.read() }
        // The handle closes the descriptor when released, which must wait until the source no longer reads it.
        source.setCancelHandler { _ = handle }
        source.resume()
    }

    /// Whether the output went beyond the limit, in which case it is incomplete.
    var exceededLimit: Bool { queue.sync { _exceededLimit } }

    /// Reads everything available without waiting; stops at the end of the output or beyond the limit.
    private func read() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fileDescriptor, &buffer, buffer.count)
            guard count > 0 else {
                if count == 0 { source.cancel() }
                return
            }
            data.append(buffer, count: count)
            if let limit, data.count > limit {
                _exceededLimit = true
                source.cancel()
                onLimitExceeded()
                return
            }
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
