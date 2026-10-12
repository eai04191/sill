import Darwin
import Foundation
import os

/// Runs `codexbar serve`, CodexBar's local HTTP server (https://github.com/steipete/CodexBar), while the usage widget
/// is shown.
///
/// The server caches each response for `refreshInterval` seconds, so it decides how often Anthropic and OpenAI are
/// asked for the usage, however often Sill reads it; a failed fetch keeps the last good response. Running it from
/// Sill, like media-control, leaves nothing for the user to set up besides installing CodexBar.
final class CodexBarServer {
    /// Homebrew links the CLI from CodexBar.app (`brew install --cask codexbar`) to one of these locations.
    /// Looked up on every launch, so that installing CodexBar while Sill runs takes effect.
    static var executableURL: URL? {
        ["/opt/homebrew/bin/codexbar", "/usr/local/bin/codexbar"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Seconds a response is cached, and so the shortest time between two fetches from each service.
    static let refreshInterval = 300
    /// Seconds before starting the server again after it exits or fails to start.
    private static let restartDelay: TimeInterval = 5
    /// Seconds between looks for the CLI while it is not installed.
    private static let installCheckInterval: TimeInterval = 30
    /// The CLI's executable behind the Homebrew link, which names the process.
    private static let processName = "CodexBarCLI"

    /// Records the server's process ID, so a server left running by a Sill that crashed is stopped on the next launch.
    private static let pidFileURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "net.mizle.sill", isDirectory: true)
        .appendingPathComponent("codexbar-serve.pid")

    /// Called on the main queue with the URL of the running server's usage endpoint, or nil once it stops.
    private let onChange: (URL?) -> Void
    /// Called on the main queue when the CLI is found missing or found again.
    private let onMissingChange: (Bool) -> Void
    private var process: Process?
    private var stopped = false
    private var isMissing = false

    init(onChange: @escaping (URL?) -> Void, onMissingChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        self.onMissingChange = onMissingChange
    }

    func start() {
        stopped = false
        Self.stopOrphan()
        launch()
    }

    func stop() {
        stopped = true
        if let process {
            // Signaled now rather than from a queue, as Sill can exit before a queued signal is sent when it quits.
            // The PID file is kept until the server is seen to exit, so one that still outlives Sill is stopped on
            // the next launch.
            process.terminate()
            ProcessStopper.stop(process, after: ProcessStopper.killGracePeriod)
        }
        process = nil
        onChange(nil)
    }

    private func launch() {
        guard let executableURL = Self.executableURL else {
            setMissing(true)
            relaunch(after: Self.installCheckInterval)
            return
        }
        setMissing(false)
        // The server takes the port as given and cannot pick one itself (`--port 0` is rejected), so a free one is
        // chosen here. Another process can take it before the server binds it, in which case the server exits and is
        // started again on another port.
        guard let port = Self.freePort() else {
            Logger.usage.error("Could not find a free port for codexbar serve")
            relaunch(after: Self.restartDelay)
            return
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["serve", "--port", String(port), "--refresh-interval", String(Self.refreshInterval)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] exited in
            Self.removePIDFile(for: exited.processIdentifier)
            Logger.usage.notice(
                "codexbar serve, pid \(exited.processIdentifier, privacy: .public), exited: reason \(exited.terminationReason.rawValue, privacy: .public), status \(exited.terminationStatus, privacy: .public)"
            )
            DispatchQueue.main.async {
                // A server stopped by `stop()` is not started again.
                guard let self, self.process === exited else { return }
                self.onChange(nil)
                self.relaunch(after: Self.restartDelay)
            }
        }
        do {
            try process.run()
            Logger.usage.notice("Started codexbar serve on port \(port, privacy: .public), pid \(process.processIdentifier, privacy: .public)")
            self.process = process
            Self.writePIDFile(process.processIdentifier)
            onChange(URL(string: "http://127.0.0.1:\(port)/usage?provider=both"))
        } catch {
            Logger.usage.error("Could not start codexbar serve: \(String(describing: error), privacy: .public)")
            relaunch(after: Self.restartDelay)
        }
    }

    private func relaunch(after delay: TimeInterval) {
        process = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped else { return }
            self.launch()
        }
    }

    private func setMissing(_ missing: Bool) {
        guard missing != isMissing else { return }
        isMissing = missing
        if missing {
            Logger.usage.error("codexbar was not found; install it with `brew install --cask codexbar`")
        }
        onMissingChange(missing)
    }

    /// A port on 127.0.0.1 that no process listens on, from the system's choice for a socket bound to port 0.
    private static func freePort() -> UInt16? {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return nil }
        defer { close(socketDescriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                bind(socketDescriptor, address, length) == 0 && getsockname(socketDescriptor, address, &length) == 0
            }
        }
        return bound ? UInt16(bigEndian: address.sin_port) : nil
    }

    // MARK: - Server Left by a Crash

    /// A child process outlives a Sill that crashes or is killed, as macOS has no way to end it with its parent. Such
    /// a server keeps about 35 MB until it is stopped, so the next launch stops it, but only when the recorded process
    /// is still CodexBar's CLI and was orphaned (its parent is now launchd), so a reused process ID or a server the
    /// user started is left alone.
    private static func stopOrphan() {
        guard let pid = recordedPID() else { return }
        removePIDFile(for: pid)
        guard processName(of: pid) == processName, parentProcessID(of: pid) == 1 else { return }
        Logger.usage.notice("Stopping codexbar serve left by an earlier run, pid \(pid, privacy: .public)")
        kill(pid, SIGTERM)
    }

    private static func processName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return (path as NSString).lastPathComponent
    }

    private static func parentProcessID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    private static func writePIDFile(_ pid: pid_t) {
        guard let pidFileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: pidFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try String(pid).write(to: pidFileURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.usage.error("Could not record the codexbar serve pid: \(String(describing: error), privacy: .public)")
        }
    }

    private static func recordedPID() -> pid_t? {
        guard let pidFileURL, let text = try? String(contentsOf: pidFileURL, encoding: .utf8) else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Removes the PID file if it still records `pid`, as a server started since may have replaced it.
    private static func removePIDFile(for pid: pid_t) {
        guard let pidFileURL, recordedPID() == pid else { return }
        try? FileManager.default.removeItem(at: pidFileURL)
    }
}
