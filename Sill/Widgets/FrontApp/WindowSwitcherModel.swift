import AppKit
import os

/// A window as AeroSpace lists it.
struct AeroSpaceWindow: Decodable, Identifiable, Equatable {
    let id: Int
    let appName: String
    let title: String
    let workspace: String
    let bundleIdentifier: String?

    /// The title, or the app name for a window without one, as the switcher shows it.
    var displayTitle: String { title.isEmpty ? appName : title }

    private enum CodingKeys: String, CodingKey {
        case id = "window-id"
        case appName = "app-name"
        case title = "window-title"
        case workspace
        case bundleIdentifier = "app-bundle-id"
    }
}

/// Runs the AeroSpace CLI (https://github.com/nikitabobko/AeroSpace), which lists and focuses windows on every
/// workspace without a permission of Sill's own.
enum AeroSpace {
    enum Failure: Error {
        /// The CLI is not installed where Homebrew puts it.
        case notInstalled
        /// The CLI did not start, failed, hung, or printed something that is not the expected output.
        case commandFailed
    }

    /// Homebrew installs AeroSpace's CLI in one of these locations. Looked up on every use, so that installing
    /// AeroSpace while Sill runs takes effect.
    static var executableURL: URL? {
        ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Seconds after which a command is stopped, as AeroSpace answers within a moment when its server runs.
    private static let timeout: TimeInterval = 5
    /// The most bytes of output read; a window list is a few hundred bytes per window.
    private static let outputLimit = 10_000_000

    /// Lists the windows on every workspace. Blocks until AeroSpace answers, so call it off the main thread.
    static func listWindows() throws -> [AeroSpaceWindow] {
        let output = try run([
            "list-windows", "--all", "--format",
            "%{window-id} %{app-name} %{window-title} %{workspace} %{app-bundle-id}", "--json",
        ])
        do {
            return try JSONDecoder().decode([AeroSpaceWindow].self, from: output)
        } catch {
            Logger.windowSwitcher.error("AeroSpace printed a window list that could not be read (\(output.count, privacy: .public) bytes): \(String(describing: error), privacy: .public)")
            throw Failure.commandFailed
        }
    }

    /// Focuses the window, switching to its workspace if needed. Blocks until AeroSpace answers, so call it off the
    /// main thread.
    static func focus(windowID: Int) throws {
        _ = try run(["focus", "--window-id", String(windowID)])
    }

    /// Runs the CLI with the arguments and returns its output, stopping it after `timeout` seconds as the usage
    /// command is (see `ProcessStopper` and `OutputReader`).
    private static func run(_ arguments: [String]) throws -> Data {
        guard let executableURL else {
            Logger.windowSwitcher.error("AeroSpace is not installed")
            throw Failure.notInstalled
        }
        let start = ContinuousClock.now
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let reader = OutputReader(pipe.fileHandleForReading, limit: outputLimit) {
            ProcessStopper.stop(process)
        }
        do {
            try process.run()
        } catch {
            _ = reader.finish()
            Logger.windowSwitcher.error("Could not start aerospace \(arguments.first ?? "", privacy: .public): \(String(describing: error), privacy: .public)")
            throw Failure.commandFailed
        }
        ProcessStopper.stop(process, after: timeout)
        process.waitUntilExit()
        let output = reader.finish()
        guard process.terminationReason == .exit, process.terminationStatus == 0, !reader.exceededLimit else {
            Logger.windowSwitcher.error(
                "aerospace \(arguments.first ?? "", privacy: .public) failed after \(secondsSince(start), format: .fixed(precision: 3), privacy: .public) s: reason \(process.terminationReason.rawValue, privacy: .public), status \(process.terminationStatus, privacy: .public), output over limit \(reader.exceededLimit, privacy: .public)"
            )
            throw Failure.commandFailed
        }
        Logger.windowSwitcher.notice(
            "aerospace \(arguments.first ?? "", privacy: .public) took \(secondsSince(start), format: .fixed(precision: 3), privacy: .public) s")
        return output
    }
}

/// The windows the switcher lists, loaded from AeroSpace each time the popup opens.
@MainActor
final class WindowSwitcherModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([AeroSpaceWindow])
        case failed(AeroSpace.Failure)
    }

    @Published private(set) var state: State = .loading
    /// Set when focusing a window failed, such as one closed after the list was loaded, so the popup says so.
    @Published private(set) var focusFailed = false
    /// The icons of the listed windows' apps, by bundle identifier, read once for each app when the list is loaded.
    private(set) var icons: [String: NSImage] = [:]

    func load() async {
        Logger.windowSwitcher.notice("Loading the window list")
        state = .loading
        let result = await Task.detached(priority: .userInitiated) {
            Result { try AeroSpace.listWindows() }
        }.value
        switch result {
        case .success(let windows):
            Logger.windowSwitcher.notice("Loaded \(windows.count, privacy: .public) windows")
            loadIcons(for: windows)
            state = .loaded(windows)
        case .failure(let error):
            state = .failed(error as? AeroSpace.Failure ?? .commandFailed)
        }
    }

    /// Reads the icon of each app in the list that has none yet. An app found by neither AeroSpace's bundle identifier
    /// nor Launch Services, such as one deleted while it runs, is listed without an icon.
    private func loadIcons(for windows: [AeroSpaceWindow]) {
        for bundleIdentifier in Set(windows.compactMap(\.bundleIdentifier)) where icons[bundleIdentifier] == nil {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { continue }
            icons[bundleIdentifier] = NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    /// Focuses the window and closes the popup, or keeps the popup open with a message and a fresh list when AeroSpace
    /// could not focus it, rather than closing as if it had. Focusing another app's window also takes key status from
    /// the popup, which closes it anyway.
    func focus(_ window: AeroSpaceWindow) async {
        focusFailed = false
        let result = await Task.detached(priority: .userInitiated) {
            Result { try AeroSpace.focus(windowID: window.id) }
        }.value
        switch result {
        case .success:
            Logger.windowSwitcher.notice("Focused window \(window.id, privacy: .public) of \(window.bundleIdentifier ?? "unknown", privacy: .public)")
            MenuBarPopup.hide()
        case .failure(let error):
            Logger.windowSwitcher.error("Could not focus window \(window.id, privacy: .public): \(String(describing: error), privacy: .public)")
            focusFailed = true
            await load()
        }
    }
}
