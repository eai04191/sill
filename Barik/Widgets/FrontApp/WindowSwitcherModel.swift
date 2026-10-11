import Foundation

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
/// workspace without a permission of Barik's own.
enum AeroSpace {
    enum Failure: Error {
        /// The CLI is not installed where Homebrew puts it.
        case notInstalled
        /// The CLI did not start, failed, hung, or printed something that is not the expected output.
        case commandFailed
    }

    /// Homebrew installs AeroSpace's CLI in one of these locations. Looked up on every use, so that installing
    /// AeroSpace while Barik runs takes effect.
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
            print("AeroSpace printed a window list that could not be read: \(error)")
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
        guard let executableURL else { throw Failure.notInstalled }
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
            print("Failed to start AeroSpace: \(error)")
            throw Failure.commandFailed
        }
        ProcessStopper.stop(process, after: timeout)
        process.waitUntilExit()
        let output = reader.finish()
        guard process.terminationReason == .exit, process.terminationStatus == 0, !reader.exceededLimit else {
            print("AeroSpace \(arguments.first ?? "") failed with status \(process.terminationStatus)")
            throw Failure.commandFailed
        }
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

    func load() async {
        state = .loading
        let result = await Task.detached(priority: .userInitiated) {
            Result { try AeroSpace.listWindows() }
        }.value
        switch result {
        case .success(let windows):
            state = .loaded(windows)
        case .failure(let error):
            state = .failed(error as? AeroSpace.Failure ?? .commandFailed)
        }
    }

    /// Closes the popup and focuses the window. Focusing another app's window also takes key status from the popup,
    /// which would close it anyway.
    func focus(_ window: AeroSpaceWindow) {
        MenuBarPopup.hide()
        Task.detached(priority: .userInitiated) {
            do {
                try AeroSpace.focus(windowID: window.id)
            } catch {
                print("Failed to focus window \(window.id) with AeroSpace: \(error)")
            }
        }
    }
}
