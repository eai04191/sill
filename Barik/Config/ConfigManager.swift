import Foundation
import SwiftUI
import TOMLDecoder

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var config = Config()
    /// Why the config could not be read at launch; Barik then stops with this error. Set during `init`.
    private(set) var initError: String?
    /// Why the config file could not be read again after launch, while the config read before stays in use. Cleared
    /// once the file is read. Set on the main thread.
    @Published private(set) var reloadError: String?
    /// Whether `config` holds the config file rather than the defaults it starts with. Read on the main thread.
    private(set) var hasLoadedConfigFile = false
    
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private let watchQueue = DispatchQueue(label: "Barik.ConfigManager.watch")
    private var configFilePath: String?

    private init() {
        loadOrCreateConfigIfNeeded()
    }

    private func loadOrCreateConfigIfNeeded() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let path1 = "\(homePath)/.barik-config.toml"
        let path2 = "\(homePath)/.config/barik/config.toml"
        var chosenPath: String?

        if FileManager.default.fileExists(atPath: path1) {
            chosenPath = path1
        } else if FileManager.default.fileExists(atPath: path2) {
            chosenPath = path2
        } else {
            do {
                try createDefaultConfig(at: path1)
                chosenPath = path1
            } catch {
                initError = "Error creating default config: \(error.localizedDescription)"
                print("Error when creating default config:", error)
                return
            }
        }

        if let path = chosenPath {
            configFilePath = path
            parseConfigFile(at: path, atLaunch: true)
            startWatchingFile(at: path)
        }
    }

    /// Reads the config file. An error at launch is kept in `initError`; an error later is published in
    /// `reloadError`, and the config read before stays in use.
    private func parseConfigFile(at path: String, atLaunch: Bool = false) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let decoder = TOMLDecoder()
            let rootToml = try decoder.decode(RootToml.self, from: content)
            DispatchQueue.main.async {
                self.hasLoadedConfigFile = true
                self.config = Config(rootToml: rootToml)
                self.reloadError = nil
            }
        } catch {
            print("Error when parsing TOML file:", error)
            if atLaunch {
                initError = "Error parsing TOML file: \(error.localizedDescription)"
            } else {
                // The localized description of a decoding error does not say what is wrong, so show the error itself.
                let message = "Error parsing \(path): \(error)"
                DispatchQueue.main.async {
                    self.reloadError = message
                }
            }
        }
    }

    private func createDefaultConfig(at path: String) throws {
        let defaultTOML = """
            theme = "system" # system, light, dark

            [widgets]
            displayed = [ # widgets on menu bar
                "spacer",
                "default.battery",
                "divider",
                # { "default.time" = { time-zone = "America/Los_Angeles", format = "E d, hh:mm" } },
                "default.time"
            ]

            [widgets.default.battery]
            show-percentage = true
            warning-level = 30
            critical-level = 10

            [widgets.default.time]
            format = "E d, J:mm"
            calendar.format = "J:mm"

            calendar.show-events = true
            # calendar.allow-list = ["Home", "Personal"] # show only these calendars
            # calendar.deny-list = ["Work", "Boss"] # show all calendars except these

            [widgets.default.time.popup]
            view-variant = "box"

            [experimental.background]
            displayed = true
            """
        try defaultTOML.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Watches the config file for changes. Editors that save atomically replace the file, so the watched file is
    /// deleted or renamed; the new file at the same path is then watched instead, and the config is read again once it
    /// exists. While the file is missing, opening it is retried with growing delays, and it is not read.
    /// Watching, rewatching and reloading all run on one serial queue, so an older reload never publishes after a
    /// newer one.
    /// - Parameters:
    ///   - reloadsWhenOpened: Reads the config once the file is opened, for a file that replaced the watched one.
    ///   - retryDelay: The delay before the next attempt when the file is missing.
    private func startWatchingFile(
        at path: String, reloadsWhenOpened: Bool = false, retryDelay: TimeInterval = 0.25
    ) {
        let descriptor = open(path, O_EVTONLY)
        fileDescriptor = descriptor
        guard descriptor != -1 else {
            // The replacing file does not exist yet; try again until it does, or later edits would go unnoticed.
            if retryDelay == 0.25 {
                print("Config file is missing, waiting for it:", path)
            }
            watchQueue.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                self?.startWatchingFile(
                    at: path, reloadsWhenOpened: true, retryDelay: min(retryDelay * 2, 5))
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename],
            queue: watchQueue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source, let path = self.configFilePath else {
                return
            }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                source.cancel()
                self.startWatchingFile(at: path, reloadsWhenOpened: true)
            } else {
                self.parseConfigFile(at: path)
            }
        }
        // Close this watcher's own descriptor; fileDescriptor may already belong to the watcher of the new file.
        source.setCancelHandler {
            close(descriptor)
        }
        fileWatchSource = source
        source.resume()
        if reloadsWhenOpened {
            parseConfigFile(at: path)
        }
    }

    /// Writes on the watch queue, where the config is also reloaded, so a reload never reads a half-written file and
    /// the reload after the write is not overtaken by an older one.
    func updateConfigValue(key: String, newValue: String) {
        watchQueue.async { [weak self] in
            guard let self else { return }
            guard let path = self.configFilePath else {
                print("Config file path is not set")
                return
            }
            do {
                let currentText = try String(contentsOfFile: path, encoding: .utf8)
                let updatedText = try TOMLKeyUpdater.updating(
                    currentText, key: key, to: newValue)
                // Not atomically: an atomic write replaces the path with a new file, which would turn a symlinked
                // config into a regular file. Writing in place goes through the symlink to the file it points to.
                try updatedText.write(
                    toFile: path, atomically: false, encoding: .utf8)
                self.parseConfigFile(at: path)
            } catch {
                print("Error updating config:", error)
            }
        }
    }

    func globalWidgetConfig(for widgetId: String) -> ConfigData {
        config.rootToml.widgets.config(for: widgetId) ?? [:]
    }

    func resolvedWidgetConfig(for item: TomlWidgetItem) -> ConfigData {
        Self.merging(item.inlineParams, into: globalWidgetConfig(for: item.id))
    }

    /// Inline values replace global ones, except tables, which are merged key by key. An inline
    /// `calendar = { format = ... }` then keeps the other keys of the global calendar table.
    private static func merging(_ overrides: ConfigData, into base: ConfigData) -> ConfigData {
        var merged = base
        for (key, value) in overrides {
            if case .dictionary(let overrideTable) = value, case .dictionary(let baseTable)? = merged[key] {
                merged[key] = .dictionary(merging(overrideTable, into: baseTable))
            } else {
                merged[key] = value
            }
        }
        return merged
    }
}
