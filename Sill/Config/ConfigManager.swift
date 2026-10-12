import Foundation
import os
import SwiftUI
import TOMLDecoder

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var config = Config()
    /// Why the config could not be read at launch; Sill then stops with this error. Set during `init`.
    private(set) var initError: String?
    /// Why the config file could not be read again after launch, while the config read before stays in use. Cleared
    /// once the file is read. Set on the main thread.
    @Published private(set) var reloadError: String?
    /// Why a change made in Sill, such as the calendar layout, could not be saved to the config file, which was then
    /// left as it was. Cleared once a later change is saved. Set on the main thread.
    @Published private(set) var updateError: String?
    /// Whether `config` holds the config file rather than the defaults it starts with. Read on the main thread.
    private(set) var hasLoadedConfigFile = false
    
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private let watchQueue = DispatchQueue(label: "Sill.ConfigManager.watch")
    private var configFilePath: String?

    /// The config file: `$XDG_CONFIG_HOME/sill/config.toml`, or `~/.config/sill/config.toml` when XDG_CONFIG_HOME is
    /// unset or not an absolute path, as the XDG Base Directory Specification says. Sill started from launchd or the
    /// Finder sees XDG_CONFIG_HOME only when it is set for them, not only in a shell's startup files.
    static let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var configHome = "\(home)/.config"
        if let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], xdgConfigHome.hasPrefix("/") {
            configHome = xdgConfigHome
        }
        return "\(configHome)/sill/config.toml"
    }()

    /// Where Sill used to keep the config, in the home folder. It is no longer read: a config there stops Sill with
    /// an error that says where to move it, rather than Sill starting with a new default config.
    private static let homeConfigPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.sill-config.toml"

    private init() {
        loadOrCreateConfigIfNeeded()
    }

    private func loadOrCreateConfigIfNeeded() {
        let path = Self.configPath
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: path) {
            if fileManager.fileExists(atPath: Self.homeConfigPath) {
                let homeConfigPath = (Self.homeConfigPath as NSString).abbreviatingWithTildeInPath
                let configPath = (path as NSString).abbreviatingWithTildeInPath
                initError = String(
                    localized: "Move \(homeConfigPath) to \(configPath). Sill no longer reads a config in the home folder.",
                    comment: "The old config file, then where it goes now.")
                Logger.config.error("The config is at \(Self.homeConfigPath, privacy: .public), which is no longer read, instead of \(path, privacy: .public)")
                return
            }
            do {
                try fileManager.createDirectory(
                    atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try createDefaultConfig(at: path)
            } catch {
                initError = String(localized: "Error creating default config: \(error.localizedDescription)")
                Logger.config.error("Could not create the default config at \(path, privacy: .public): \(String(describing: error), privacy: .public)")
                return
            }
            Logger.config.notice("Created the default config at \(path, privacy: .public)")
        }

        configFilePath = path
        parseConfigFile(at: path, atLaunch: true)
        startWatchingFile(at: path)
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
            Logger.config.error("Could not read \(path, privacy: .public): \(String(describing: error), privacy: .public)")
            if atLaunch {
                initError = String(localized: "Error parsing TOML file: \(error.localizedDescription)")
            } else {
                // The localized description of a decoding error does not say what is wrong, so show the error itself.
                let message = String(localized: "Error parsing \(path): \(String(describing: error))")
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
                "default.battery",
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
            # weekday-english = true # show the English weekday names under the locale's
            # month-english = true # list the months with their numbers and English names under the days
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
                Logger.config.notice("\(path, privacy: .public) is missing; waiting for it")
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

    /// The config file changed between reading it for an update and replacing it, so the update was not saved.
    private struct ConfigFileChanged: LocalizedError {
        var errorDescription: String? { String(localized: "The config file changed while the change was being saved.") }
    }

    /// Writes on the watch queue, where the config is also reloaded, so a reload never reads a half-written file and
    /// the reload after the write is not overtaken by an older one. A failure is published in `updateError`.
    func updateConfigValue(key: String, newValue: String) {
        watchQueue.async { [weak self] in
            guard let self else { return }
            guard let path = self.configFilePath else {
                Logger.config.error("Could not save \(key, privacy: .public): the config file path is not set")
                return
            }
            do {
                try Self.replaceValue(key: key, newValue: newValue, inFileAt: path)
                DispatchQueue.main.async { self.updateError = nil }
                self.parseConfigFile(at: path)
            } catch {
                Logger.config.error("Could not save \(key, privacy: .public) to \(path, privacy: .public): \(String(describing: error), privacy: .public)")
                let message = String(
                    localized: "Could not save \(key) to \(path): \(error.localizedDescription)",
                    comment: "The config key, the config file's path, and the error.")
                DispatchQueue.main.async { self.updateError = message }
            }
        }
    }

    /// Replaces the file the path leads to with a copy that has the new value, so a write that fails partway leaves
    /// the file as it was instead of cut off. The copy is written next to the file a symlink points to, such as a
    /// config kept in a dotfiles repository, and renamed over it, so the symlink stays. The file watcher sees the old
    /// file deleted and watches the new one (see `startWatchingFile`).
    ///
    /// The file is not replaced when its contents changed since they were read, as by an editor saving it meanwhile,
    /// whose edit would otherwise be lost. A change between that check and the rename is still overwritten; the window
    /// is a single system call, and closing it would need a lock that editors do not take.
    private static func replaceValue(key: String, newValue: String, inFileAt path: String) throws {
        let fileURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let original = try Data(contentsOf: fileURL)
        guard let currentText = String(data: original, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let updatedText = try TOMLKeyUpdater.updating(currentText, key: key, to: newValue)
        let temporaryURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).sill-\(UUID().uuidString)")
        do {
            try Data(updatedText.utf8).write(to: temporaryURL)
            // The new file keeps the permissions of the file it replaces.
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let permissions = attributes[.posixPermissions] {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporaryURL.path)
            }
            guard try Data(contentsOf: fileURL) == original else { throw ConfigFileChanged() }
            guard rename(temporaryURL.path, fileURL.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
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
