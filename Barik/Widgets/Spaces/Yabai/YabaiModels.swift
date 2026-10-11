import AppKit

struct YabaiWindow: WindowModel {
    let id: Int
    let title: String
    let appName: String?
    let pid: pid_t
    let isFocused: Bool
    let stackIndex: Int
    var appIcon: NSImage?
    let isHidden: Bool
    let isMinimized: Bool
    let isSticky: Bool
    let spaceId: Int

    enum CodingKeys: String, CodingKey {
        case id
        case spaceId = "space"
        case title
        case appName = "app"
        case pid
        case isFocused = "has-focus"
        case stackIndex = "stack-index"
        case isHidden = "is-hidden"
        case isMinimized = "is-minimized"
        case isSticky = "is-sticky"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        spaceId = try container.decode(Int.self, forKey: .spaceId)
        title =
            try container.decodeIfPresent(String.self, forKey: .title)
            ?? "Unnamed"
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        isFocused = try container.decode(Bool.self, forKey: .isFocused)
        stackIndex =
            try container.decodeIfPresent(Int.self, forKey: .stackIndex) ?? 0
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
        isMinimized = try container.decode(Bool.self, forKey: .isMinimized)
        isSticky = try container.decode(Bool.self, forKey: .isSticky)
        pid = try container.decode(pid_t.self, forKey: .pid)
        appIcon = IconCache.shared.icon(forProcess: pid)
    }
}

struct YabaiSpace: SpaceModel {
    typealias WindowType = YabaiWindow
    let id: Int
    var isFocused: Bool
    var windows: [YabaiWindow] = []

    enum CodingKeys: String, CodingKey {
        case id = "index"
        case isFocused = "has-focus"
    }
}
