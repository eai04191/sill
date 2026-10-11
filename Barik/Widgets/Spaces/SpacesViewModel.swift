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
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didTerminateApplicationNotification,
        NSWorkspace.didHideApplicationNotification,
        NSWorkspace.didUnhideApplicationNotification,
    ]

    @Published var spaces: [AnySpace] = []
    private var timer: Timer?
    private var provider: AnySpacesProvider?
    /// Runs one fetch at a time, so the CLI calls of a slow fetch do not pile up behind each other.
    private let fetchQueue = DispatchQueue(label: "Barik.SpacesViewModel.fetch", qos: .utility)
    /// Whether a fetch is running, and whether another one was requested meanwhile. Used on the main thread.
    private var isFetching = false
    private var fetchesAgain = false
    private var observers: [NSObjectProtocol] = []
    /// The last error printed, so a failure that lasts is printed once instead of on every fetch.
    private var lastPrintedError: String?

    init() {
        let runningApps = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        if runningApps.contains("yabai") {
            provider = AnySpacesProvider(YabaiSpacesProvider())
        } else if runningApps.contains("aerospace") {
            provider = AnySpacesProvider(AerospaceSpacesProvider())
        } else {
            provider = nil
        }
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) {
            [weak self] _ in
            self?.loadSpaces()
        }
        let center = NSWorkspace.shared.notificationCenter
        observers = Self.changeNotifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.requestSpaces()
            }
        }
        loadSpaces()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
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
    /// ran, and only when they differ from the shown spaces.
    private func loadSpaces() {
        guard !isFetching else { return }
        guard let provider else {
            apply([])
            return
        }
        isFetching = true
        fetchQueue.async { [weak self] in
            let result = Result { try provider.getSpacesWithWindows() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                switch result {
                case .success(let spaces):
                    self.lastPrintedError = nil
                    self.apply(spaces.sorted { $0.id < $1.id })
                case .failure(let error):
                    let message = "\(error)"
                    if message != self.lastPrintedError {
                        print("Spaces: \(message)")
                        self.lastPrintedError = message
                    }
                    self.apply([])
                }
                if self.fetchesAgain {
                    self.fetchesAgain = false
                    self.loadSpaces()
                }
            }
        }
    }

    private func apply(_ spaces: [AnySpace]) {
        if spaces != self.spaces {
            self.spaces = spaces
        }
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.provider?.focusSpace(
                    spaceId: space.id, needWindowFocus: needWindowFocus)
            } catch {
                print("Spaces: \(error)")
            }
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.provider?.focusWindow(windowId: String(window.id))
            } catch {
                print("Spaces: \(error)")
            }
        }
    }
}

class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {}
    func icon(for appName: String) -> NSImage? {
        if let cached = cache.object(forKey: appName as NSString) {
            return cached
        }
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: {
            $0.localizedName == appName
        }),
            let bundleURL = app.bundleURL
        {
            let icon = workspace.icon(forFile: bundleURL.path)
            cache.setObject(icon, forKey: appName as NSString)
            return icon
        }
        return nil
    }
}
