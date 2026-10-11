import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    /// One view model, with its polling, for all spaces widgets on the bar.
    static let inUse = SharedWhileInUse<SpacesViewModel>()

    /// AeroSpace and yabai can only notify other apps through commands set in their own config, so the spaces are
    /// polled. Changes that come with a workspace notification, such as switching apps, are fetched right away.
    private static let pollInterval: TimeInterval = 1
    private static let changeNotifications: [Notification.Name] = [
        NSWorkspace.activeSpaceDidChangeNotification,
        NSWorkspace.didActivateApplicationNotification,
        NSWorkspace.didHideApplicationNotification,
        NSWorkspace.didUnhideApplicationNotification,
    ]
    /// The window manager may start or quit after Barik, so the provider is picked again when an app launches or quits.
    private static let appListNotifications: [Notification.Name] = [
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didTerminateApplicationNotification,
    ]

    @Published var spaces: [AnySpace] = []
    private var timer: Timer?
    private var provider: AnySpacesProvider?
    /// Runs one fetch at a time, so the CLI calls of a slow fetch do not pile up behind each other.
    private let fetchQueue = DispatchQueue(label: "Barik.SpacesViewModel.fetch", qos: .utility)
    private let commandQueue = DispatchQueue(label: "Barik.SpacesViewModel.command", qos: .userInitiated)
    /// Whether a fetch is running, and whether another one was requested meanwhile. Used on the main thread.
    private var isFetching = false
    private var fetchesAgain = false
    private var observers: [NSObjectProtocol] = []
    private var configCancellable: AnyCancellable?
    /// The window manager and CLI path the provider was made for, or nil when there is no provider.
    private var providerSource: String?
    /// The last error printed, so a failure that lasts is printed once instead of on every fetch.
    private var lastPrintedError: String?

    init() {
        let center = NSWorkspace.shared.notificationCenter
        observers =
            Self.changeNotifications.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.requestSpaces()
                }
            }
            + Self.appListNotifications.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.updateProvider(config: ConfigManager.shared.config)
                    self?.requestSpaces()
                }
            }
        // The publisher sends the current config right away, which picks the first provider. It sends before the
        // config property changes, so the new config is passed along instead of read from the manager.
        configCancellable = ConfigManager.shared.$config.sink { [weak self] config in
            self?.updateProvider(config: config)
        }
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    /// Makes the provider for the running window manager with the CLI path from `config`, and polls only while there
    /// is one. A CLI path without an executable is reported once and gives no provider, instead of a failing call on
    /// every poll.
    private func updateProvider(config: Config) {
        let runningApps = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        let windowManager: (name: String, path: String)?
        if runningApps.contains("yabai") {
            windowManager = ("yabai", config.yabai.path)
        } else if runningApps.contains("aerospace") {
            windowManager = ("aerospace", config.aerospace.path)
        } else {
            windowManager = nil
        }
        let source = windowManager.map { "\($0.name) at \($0.path)" }
        guard source != providerSource else { return }
        providerSource = source
        lastPrintedError = nil

        if let windowManager, !FileManager.default.isExecutableFile(atPath: windowManager.path) {
            print(
                "Spaces: \(windowManager.name) is running, but \(windowManager.path) is not an executable. "
                    + "Set \(windowManager.name).path in the config.")
            provider = nil
        } else if let windowManager {
            provider =
                windowManager.name == "yabai"
                ? AnySpacesProvider(YabaiSpacesProvider(executablePath: windowManager.path))
                : AnySpacesProvider(AerospaceSpacesProvider(executablePath: windowManager.path))
        } else {
            provider = nil
        }

        if provider == nil {
            timer?.invalidate()
            timer = nil
            apply([])
        } else {
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) {
                    [weak self] _ in
                    self?.loadSpaces()
                }
            }
            requestSpaces()
        }
    }

    /// Fetches the spaces now, or once the running fetch ends, since it may have read the state before the change.
    private func requestSpaces() {
        if isFetching {
            fetchesAgain = true
        } else {
            loadSpaces()
        }
    }

    /// Fetches the spaces unless a fetch is running. Results are applied on the main thread in the order the fetches
    /// ran, and only when they differ from the shown spaces. The spaces keep the order the provider lists them in.
    private func loadSpaces() {
        guard !isFetching, let provider else { return }
        isFetching = true
        fetchQueue.async { [weak self] in
            let result = Result { try provider.getSpacesWithWindows() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                // A result from a provider that was replaced meanwhile is dropped. The new provider requested a fetch.
                if provider === self.provider {
                    self.apply(result)
                }
                if self.fetchesAgain {
                    self.fetchesAgain = false
                    self.loadSpaces()
                }
            }
        }
    }

    private func apply(_ result: Result<[AnySpace], Error>) {
        switch result {
        case .success(let spaces):
            lastPrintedError = nil
            apply(spaces)
        case .failure(let error):
            let message = "\(error)"
            if message != lastPrintedError {
                print("Spaces: \(message)")
                lastPrintedError = message
            }
            apply([])
        }
    }

    private func apply(_ spaces: [AnySpace]) {
        if spaces != self.spaces {
            self.spaces = spaces
        }
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        runCommand { provider in
            try provider.focusSpace(spaceId: space.id, needWindowFocus: needWindowFocus)
        }
    }

    func switchToWindow(_ window: AnyWindow, in space: AnySpace) {
        runCommand { provider in
            try provider.focusWindow(
                windowId: String(window.id), spaceId: space.id, spaceIsFocused: space.isFocused)
        }
    }

    /// Runs a focus command off the main thread. Commands run one at a time in the order they were given, and the
    /// spaces are fetched once each one ends.
    private func runCommand(_ command: @escaping (AnySpacesProvider) throws -> Void) {
        guard let provider else { return }
        commandQueue.async { [weak self] in
            do {
                try command(provider)
            } catch {
                print("Spaces: \(error)")
            }
            DispatchQueue.main.async {
                self?.requestSpaces()
            }
        }
    }
}

/// App icons by process identifier, so apps with the same name keep their own icons. A running app without a bundle
/// icon is cached too, instead of being looked up again on every fetch. A process that is not known as an app yet,
/// such as one that has just launched, is looked up again next time.
final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSNumber, CachedIcon>()
    private init() {}

    func icon(forProcess pid: pid_t) -> NSImage? {
        let key = NSNumber(value: pid)
        if let cached = cache.object(forKey: key) {
            return cached.image
        }
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }
        let image = app.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache.setObject(CachedIcon(image), forKey: key)
        return image
    }

    private final class CachedIcon {
        let image: NSImage?

        init(_ image: NSImage?) {
            self.image = image
        }
    }
}
