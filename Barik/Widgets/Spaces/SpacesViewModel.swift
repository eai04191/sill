import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    /// One view model, polling every 0.1 seconds, for all spaces widgets on the bar.
    static let inUse = SharedWhileInUse<SpacesViewModel>()

    @Published var spaces: [AnySpace] = []
    private var timer: Timer?
    private var provider: AnySpacesProvider?
    /// Runs one fetch at a time, so the CLI calls of a slow fetch do not pile up behind each other.
    private let fetchQueue = DispatchQueue(label: "Barik.SpacesViewModel.fetch", qos: .utility)
    /// Whether a fetch is running. Read and written on the main thread.
    private var isFetching = false
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            self?.loadSpaces()
        }
        loadSpaces()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
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
