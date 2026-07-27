import Foundation
import Testing
@testable import Weekflow

@Suite("App data location isolation")
struct AppDataLocationTests {
    @Test("resolves a Swift package directory directly")
    func resolvesPackageDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Package.swift")
        FileManager.default.createFile(atPath: package.path, contents: Data())

        let executable = root.appendingPathComponent(".build/debug/Weekflow")
        let result = AppDataLocation.projectDataDirectory(
            startingAt: executable.deletingLastPathComponent()
        )

        #expect(result == root.appendingPathComponent(".data", isDirectory: true))
    }

    @Test("resolves the workspace from a packaged debug app under the repository root")
    func resolvesPackagedDebugApp() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("01_workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let package = workspace.appendingPathComponent("Package.swift")
        FileManager.default.createFile(atPath: package.path, contents: Data())

        let appExecutableDirectory = root
            .appendingPathComponent("dist/Weekflow.app/Contents/MacOS", isDirectory: true)
        let result = AppDataLocation.projectDataDirectory(startingAt: appExecutableDirectory)

        #expect(result == workspace.appendingPathComponent(".data", isDirectory: true))
    }

    @Test("does not invent a system fallback when no project exists")
    func unresolvedProjectReturnsNil() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(AppDataLocation.projectDataDirectory(startingAt: root) == nil)
    }

    @Test("local persistence directories are private to the current user")
    func localPersistenceDirectoriesUsePrivatePermissions() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: root.path
        )

        let storage = LocalStorage(baseDirectory: root)
        #expect(storage.initializationError == nil)
        try storage.savePlans([])

        let rootPermissions = try #require(
            FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        )
        let databasePermissions = try #require(
            FileManager.default.attributesOfItem(atPath: storage.dataDirectoryURL.path)[.posixPermissions] as? NSNumber
        )
        #expect(rootPermissions.intValue & 0o777 == 0o700)
        #expect(databasePermissions.intValue & 0o777 == 0o700)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Weekflow-AppDataLocationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
