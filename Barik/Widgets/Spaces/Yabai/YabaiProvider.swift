import Foundation

class YabaiSpacesProvider: SpacesProvider, SwitchableSpacesProvider {
    typealias SpaceType = YabaiSpace
    let executablePath: String

    init(executablePath: String) {
        self.executablePath = executablePath
    }

    private func runYabaiCommand(arguments: [String]) throws -> Data {
        try runSpacesCommand(executablePath: executablePath, arguments: arguments)
    }

    private func fetchSpaces() throws -> [YabaiSpace] {
        let data = try runYabaiCommand(arguments: ["-m", "query", "--spaces"])
        return try JSONDecoder().decode([YabaiSpace].self, from: data)
    }

    private func fetchWindows() throws -> [YabaiWindow] {
        let data = try runYabaiCommand(arguments: ["-m", "query", "--windows"])
        return try JSONDecoder().decode([YabaiWindow].self, from: data)
    }

    func getSpacesWithWindows() throws -> [YabaiSpace] {
        let spaces = try fetchSpaces()
        let windows = try fetchWindows()
        let filteredWindows = windows.filter {
            !($0.isHidden || $0.isFloating || $0.isSticky)
        }
        var spaceDict = Dictionary(
            uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        for window in filteredWindows {
            if var space = spaceDict[window.spaceId] {
                space.windows.append(window)
                spaceDict[window.spaceId] = space
            }
        }
        // Keeps the order of the query, which is the order of the space indexes.
        var resultSpaces = spaces.compactMap { spaceDict[$0.id] }
        for i in 0..<resultSpaces.count {
            resultSpaces[i].windows.sort { $0.stackIndex < $1.stackIndex }
        }
        // Spaces without windows are left out, except the focused one, so the bar still shows where the user is.
        return resultSpaces.filter { !$0.windows.isEmpty || $0.isFocused }
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) throws {
        _ = try runYabaiCommand(arguments: ["-m", "space", "--focus", spaceId])
        if !needWindowFocus { return }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 0.1
        ) {
            do {
                let spaces = try self.getSpacesWithWindows()
                if let space = spaces.first(where: { $0.id == Int(spaceId) }) {
                    let hasFocused = space.windows.contains { $0.isFocused }
                    if !hasFocused, let firstWindow = space.windows.first {
                        _ = try self.runYabaiCommand(arguments: [
                            "-m", "window", "--focus", String(firstWindow.id),
                        ])
                    }
                }
            } catch {
                print("Spaces: \(error)")
            }
        }
    }

    /// Switches to the window's space first, as Barik did before, since focusing a window on another space may need
    /// the scripting addition. yabai fails to focus the space that is already focused, so that space is not focused.
    func focusWindow(windowId: String, spaceId: String, spaceIsFocused: Bool) throws {
        if !spaceIsFocused {
            _ = try runYabaiCommand(arguments: ["-m", "space", "--focus", spaceId])
        }
        _ = try runYabaiCommand(arguments: ["-m", "window", "--focus", windowId])
    }
}
