import AppKit

protocol SpaceModel: Identifiable, Equatable, Codable {
    associatedtype WindowType: WindowModel
    var isFocused: Bool { get set }
    var windows: [WindowType] { get set }
}

protocol WindowModel: Identifiable, Equatable, Codable {
    var id: Int { get }
    var title: String { get }
    var appName: String? { get }
    var isFocused: Bool { get }
    var appIcon: NSImage? { get set }
}

protocol SpacesProvider {
    associatedtype SpaceType: SpaceModel
    func getSpacesWithWindows() throws -> [SpaceType]
}

protocol SwitchableSpacesProvider: SpacesProvider {
    func focusSpace(spaceId: String, needWindowFocus: Bool) throws
    /// Focuses a window and switches to its space.
    func focusWindow(windowId: String, spaceId: String) throws
}

struct AnyWindow: Identifiable, Equatable {
    let id: Int
    let title: String
    let appName: String?
    let isFocused: Bool
    let appIcon: NSImage?

    init<W: WindowModel>(_ window: W) {
        self.id = window.id
        self.title = window.title
        self.appName = window.appName
        self.isFocused = window.isFocused
        self.appIcon = window.appIcon
    }

    /// Icons are compared by identity: the icon cache returns the same image for an app, and a window whose icon was
    /// not found yet differs once it is, so the spaces are published again.
    static func == (lhs: AnyWindow, rhs: AnyWindow) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title
            && lhs.appName == rhs.appName && lhs.isFocused == rhs.isFocused
            && lhs.appIcon === rhs.appIcon
    }
}

struct AnySpace: Identifiable, Equatable {
    let id: String
    let isFocused: Bool
    let windows: [AnyWindow]

    init<S: SpaceModel>(_ space: S) {
        if let aero = space as? AeroSpace {
            self.id = aero.workspace
        } else if let yabai = space as? YabaiSpace {
            self.id = String(yabai.id)
        } else {
            self.id = "0"
        }
        self.isFocused = space.isFocused
        self.windows = space.windows.map { AnyWindow($0) }
    }

    static func == (lhs: AnySpace, rhs: AnySpace) -> Bool {
        return lhs.id == rhs.id && lhs.isFocused == rhs.isFocused
            && lhs.windows == rhs.windows
    }
}

class AnySpacesProvider {
    private let _getSpacesWithWindows: () throws -> [AnySpace]
    private let _focusSpace: ((String, Bool) throws -> Void)?
    private let _focusWindow: ((String, String) throws -> Void)?

    init<P: SpacesProvider>(_ provider: P) {
        _getSpacesWithWindows = {
            try provider.getSpacesWithWindows().map { AnySpace($0) }
        }
        if let switchable = provider as? any SwitchableSpacesProvider {
            _focusSpace = { spaceId, needWindowFocus in
                try switchable.focusSpace(
                    spaceId: spaceId, needWindowFocus: needWindowFocus)
            }
            _focusWindow = { windowId, spaceId in
                try switchable.focusWindow(windowId: windowId, spaceId: spaceId)
            }
        } else {
            _focusSpace = nil
            _focusWindow = nil
        }
    }

    func getSpacesWithWindows() throws -> [AnySpace] {
        try _getSpacesWithWindows()
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) throws {
        try _focusSpace?(spaceId, needWindowFocus)
    }

    func focusWindow(windowId: String, spaceId: String) throws {
        try _focusWindow?(windowId, spaceId)
    }
}
