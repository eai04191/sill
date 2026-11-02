import Foundation
import Testing

@testable import Sill

/// Telling that the CLI behind a link was replaced, as updating CodexBar does under a running codexbar serve.
struct FileIdentityTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func sameFileThroughLink() throws {
        let file = directory.appendingPathComponent("CodexBarCLI")
        try Data("old".utf8).write(to: file)
        let link = directory.appendingPathComponent("codexbar")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        #expect(FileIdentity(of: link) != nil)
        #expect(FileIdentity(of: link) == FileIdentity(of: file))
    }

    @Test func replacedFileBehindLink() throws {
        let file = directory.appendingPathComponent("CodexBarCLI")
        try Data("old".utf8).write(to: file)
        let link = directory.appendingPathComponent("codexbar")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let launched = FileIdentity(of: link)

        let replacement = directory.appendingPathComponent("CodexBarCLI.new")
        try Data("new".utf8).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: replacement)

        #expect(FileIdentity(of: link) != launched)
    }

    @Test func missingFile() {
        #expect(FileIdentity(of: directory.appendingPathComponent("codexbar")) == nil)
    }
}
