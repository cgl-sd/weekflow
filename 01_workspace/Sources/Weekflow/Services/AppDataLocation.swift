import Foundation

/// Resolves the persistence root without allowing development and installed
/// application data to overlap.
enum AppDataLocation {
    static let projectDataDirectoryName = ".data"
    static let workspaceDirectoryName = "01_workspace"
    static let packageManifestName = "Package.swift"

    static func systemDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Weekflow", isDirectory: true)
    }

#if DEBUG
    /// DEBUG builds must resolve a project-owned directory. They intentionally
    /// fail instead of falling back to Application Support, because a fallback
    /// could make test runs read or mutate an installed app's user data.
    static func developmentDirectory(
        fileManager: FileManager = .default,
        executableURL: URL = URL(fileURLWithPath: CommandLine.arguments[0]),
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL {
        if let override = ProcessInfo.processInfo.environment["WEEKFLOW_PROJECT_ROOT"],
           let directory = projectDataDirectory(
               startingAt: URL(fileURLWithPath: override, isDirectory: true),
               fileManager: fileManager
           ) {
            return directory
        }

        for startingURL in [
            executableURL.resolvingSymlinksInPath().deletingLastPathComponent(),
            currentDirectoryURL.resolvingSymlinksInPath()
        ] {
            if let directory = projectDataDirectory(startingAt: startingURL, fileManager: fileManager) {
                return directory
            }
        }

        fatalError(
            "DEBUG 构建无法定位 Weekflow 项目目录。为防止误用正式数据，应用已停止；" +
            "请从项目内启动，或设置 WEEKFLOW_PROJECT_ROOT。"
        )
    }

    static func projectDataDirectory(
        startingAt startingURL: URL,
        fileManager: FileManager = .default,
        maximumParentCount: Int = 12
    ) -> URL? {
        var current = startingURL.standardizedFileURL

        for _ in 0...maximumParentCount {
            let directManifest = current.appendingPathComponent(packageManifestName)
            if fileManager.fileExists(atPath: directManifest.path) {
                return current.appendingPathComponent(projectDataDirectoryName, isDirectory: true)
            }

            let workspace = current.appendingPathComponent(workspaceDirectoryName, isDirectory: true)
            let nestedManifest = workspace.appendingPathComponent(packageManifestName)
            if fileManager.fileExists(atPath: nestedManifest.path) {
                return workspace.appendingPathComponent(projectDataDirectoryName, isDirectory: true)
            }

            let parent = current.deletingLastPathComponent()
            guard parent != current else { break }
            current = parent
        }
        return nil
    }
#endif

    static func runtimeDirectory(fileManager: FileManager = .default) -> URL {
#if DEBUG
        developmentDirectory(fileManager: fileManager)
#else
        systemDirectory(fileManager: fileManager)
#endif
    }
}
