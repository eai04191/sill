import Foundation

class AerospaceSpacesProvider: SpacesProvider, SwitchableSpacesProvider {
    typealias SpaceType = AeroSpace
    let executablePath: String

    init(executablePath: String) {
        self.executablePath = executablePath
    }

    func getSpacesWithWindows() throws -> [AeroSpace] {
        var spaces = try fetchSpaces()
        let windows = try fetchWindows()
        let focusedSpace = try fetchFocusedSpace()
        if let focusedSpace {
            for i in 0..<spaces.count {
                spaces[i].isFocused = (spaces[i].id == focusedSpace.id)
            }
        }
        let focusedWindow = try fetchFocusedWindow()
        var spaceDict = Dictionary(
            uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        for window in windows {
            var mutableWindow = window
            if let focused = focusedWindow, window.id == focused.id {
                mutableWindow.isFocused = true
            }
            if let ws = mutableWindow.workspace, !ws.isEmpty {
                if var space = spaceDict[ws] {
                    space.windows.append(mutableWindow)
                    spaceDict[ws] = space
                }
            } else if let focusedSpace {
                if var space = spaceDict[focusedSpace.id] {
                    space.windows.append(mutableWindow)
                    spaceDict[focusedSpace.id] = space
                }
            }
        }
        // Keeps the order of list-workspaces, which sorts names with numbers by value, so 2 comes before 10.
        var resultSpaces = spaces.compactMap { spaceDict[$0.id] }
        for i in 0..<resultSpaces.count {
            resultSpaces[i].windows.sort { $0.id < $1.id }
        }
        // Spaces without windows are left out, except the focused one, so the bar still shows where the user is.
        return resultSpaces.filter { !$0.windows.isEmpty || $0.isFocused }
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) throws {
        _ = try runAerospaceCommand(arguments: ["workspace", spaceId])
    }

    func focusWindow(windowId: String) throws {
        _ = try runAerospaceCommand(arguments: ["focus", "--window-id", windowId])
    }

    private func runAerospaceCommand(arguments: [String]) throws -> Data {
        try runSpacesCommand(executablePath: executablePath, arguments: arguments)
    }

    private func fetchSpaces() throws -> [AeroSpace] {
        let data = try runAerospaceCommand(arguments: [
            "list-workspaces", "--all", "--json",
        ])
        return try JSONDecoder().decode([AeroSpace].self, from: data)
    }

    private func fetchWindows() throws -> [AeroWindow] {
        let data = try runAerospaceCommand(arguments: [
            "list-windows", "--all", "--json", "--format",
            "%{window-id} %{app-name} %{window-title} %{workspace}",
        ])
        return try JSONDecoder().decode([AeroWindow].self, from: data)
    }

    private func fetchFocusedSpace() throws -> AeroSpace? {
        let data = try runAerospaceCommand(arguments: [
            "list-workspaces", "--focused", "--json",
        ])
        return try JSONDecoder().decode([AeroSpace].self, from: data).first
    }

    private func fetchFocusedWindow() throws -> AeroWindow? {
        let data: Data
        do {
            data = try runAerospaceCommand(arguments: [
                "list-windows", "--focused", "--json",
            ])
        } catch let error as SpacesCommandError
            where error.standardError == Self.noWindowIsFocused
        {
            return nil
        }
        return try JSONDecoder().decode([AeroWindow].self, from: data).first
    }

    /// The error `list-windows --focused` exits with when the focused workspace has no window, such as an empty one.
    private static let noWindowIsFocused = "No window is focused"
}
