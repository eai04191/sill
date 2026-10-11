import Foundation

/// A window manager CLI call that did not succeed.
struct SpacesCommandError: Error, CustomStringConvertible {
    let description: String
    /// What the CLI wrote to standard error when it exited with a nonzero status, trimmed.
    var standardError = ""
}

/// Runs a window manager CLI and returns its standard output.
///
/// Throws when the CLI cannot start, exits with a nonzero status (with its standard error in the message), or runs
/// longer than `timeout`, in which case it is killed. A hung CLI would otherwise block the calling thread forever,
/// and a failing one would hand its empty output to the JSON decoder.
func runSpacesCommand(
    executablePath: String, arguments: [String], timeout: TimeInterval = 2
) throws -> Data {
    let command = ([executablePath] + arguments).joined(separator: " ")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    do {
        try process.run()
    } catch {
        throw SpacesCommandError(description: "\(command): \(error.localizedDescription)")
    }

    // Both pipes are read while the CLI runs, so a full pipe cannot block it. They reach the end once it exits.
    let output = PipeReader(outputPipe)
    let errorOutput = PipeReader(errorPipe)
    let reads = DispatchGroup()
    output.read(in: reads)
    errorOutput.read(in: reads)
    if reads.wait(timeout: .now() + timeout) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        reads.wait()
        process.waitUntilExit()
        throw SpacesCommandError(description: "\(command): timed out after \(timeout) seconds")
    }
    process.waitUntilExit()

    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
        let message = String(decoding: errorOutput.data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw SpacesCommandError(
            description: "\(command): exited with status \(process.terminationStatus): \(message)",
            standardError: message)
    }
    return output.data
}

/// Reads a pipe to its end on a background queue. `data` is read after the dispatch group finishes.
private final class PipeReader {
    private let pipe: Pipe
    private(set) var data = Data()

    init(_ pipe: Pipe) {
        self.pipe = pipe
    }

    func read(in group: DispatchGroup) {
        DispatchQueue.global(qos: .utility).async(group: group) {
            self.data = self.pipe.fileHandleForReading.readDataToEndOfFile()
        }
    }
}
