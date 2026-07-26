import Foundation

struct AppUpdateResult: Equatable, Sendable {
    let currentVersion: String
    let latestVersion: String
    let releaseURL: URL

    var isUpdateAvailable: Bool {
        AppUpdateService.compareVersions(latestVersion, currentVersion) == .orderedDescending
    }
}

enum AppUpdateError: LocalizedError, Equatable {
    case invalidCurrentVersion
    case invalidResponse
    case requestFailed(Int)
    case responseTooLarge
    case invalidRelease

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion:
            "无法读取当前应用版本。"
        case .invalidResponse:
            "GitHub 返回了无法识别的响应。"
        case let .requestFailed(statusCode):
            "检查更新失败（HTTP \(statusCode)）。"
        case .responseTooLarge:
            "GitHub 返回的数据超过安全限制。"
        case .invalidRelease:
            "GitHub 返回的版本信息无效。"
        }
    }
}

struct AppUpdateService: Sendable {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let latestReleaseEndpoint = URL(
        string: "https://api.github.com/repos/cgl-sd/weekflow/releases/latest"
    )!
    static let latestReleasePage = URL(
        string: "https://github.com/cgl-sd/weekflow/releases/latest"
    )!
    static let maximumResponseBytes = 64 * 1_024

    private let load: Loader

    init(loader: @escaping Loader = AppUpdateService.defaultLoader()) {
        self.load = loader
    }

    func check(currentVersion: String) async throws -> AppUpdateResult {
        guard Self.versionComponents(currentVersion) != nil else {
            throw AppUpdateError.invalidCurrentVersion
        }

        var request = URLRequest(
            url: Self.latestReleaseEndpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 12
        )
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Weekflow-Update-Checker", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await load(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            return try await checkReleasePage(currentVersion: currentVersion)
        }
        guard httpResponse.statusCode == 200 else {
            throw AppUpdateError.requestFailed(httpResponse.statusCode)
        }
        guard Self.isTrustedAPIResponse(httpResponse.url) else {
            throw AppUpdateError.invalidResponse
        }
        if let declaredLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let byteCount = Int(declaredLength),
           byteCount > Self.maximumResponseBytes {
            throw AppUpdateError.responseTooLarge
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw AppUpdateError.responseTooLarge
        }

        let release: LatestRelease
        do {
            release = try JSONDecoder().decode(LatestRelease.self, from: data)
        } catch {
            throw AppUpdateError.invalidRelease
        }
        guard Self.versionComponents(release.tagName) != nil,
              Self.isTrustedReleaseURL(release.htmlURL) else {
            throw AppUpdateError.invalidRelease
        }

        return AppUpdateResult(
            currentVersion: currentVersion,
            latestVersion: release.tagName,
            releaseURL: release.htmlURL
        )
    }

    private func checkReleasePage(currentVersion: String) async throws -> AppUpdateResult {
        var request = URLRequest(
            url: Self.latestReleasePage,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 12
        )
        request.httpMethod = "HEAD"
        request.setValue("Weekflow-Update-Checker", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await load(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw AppUpdateError.requestFailed(httpResponse.statusCode)
        }
        guard let releaseURL = httpResponse.url,
              Self.isTrustedReleaseURL(releaseURL),
              let latestVersion = releaseURL.pathComponents.last,
              Self.versionComponents(latestVersion) != nil else {
            throw AppUpdateError.invalidRelease
        }
        return AppUpdateResult(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseURL: releaseURL
        )
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        guard var left = versionComponents(lhs), var right = versionComponents(rhs) else {
            return .orderedSame
        }
        let count = max(left.count, right.count)
        left.append(contentsOf: repeatElement(0, count: count - left.count))
        right.append(contentsOf: repeatElement(0, count: count - right.count))
        for (leftPart, rightPart) in zip(left, right) where leftPart != rightPart {
            return leftPart < rightPart ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    static func versionComponents(_ version: String) -> [Int]? {
        var normalized = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("v") {
            normalized.removeFirst()
        }
        guard !normalized.isEmpty, normalized.count <= 64 else { return nil }
        let core = normalized.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalized
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  let value = Int(part),
                  value <= 999_999 else { return nil }
            components.append(value)
        }
        return components
    }

    private static func defaultLoader() -> Loader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        return { request in
            try await session.data(for: request)
        }
    }

    private static func isTrustedAPIResponse(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "api.github.com"
            && url.path == "/repos/cgl-sd/weekflow/releases/latest"
    }

    private static func isTrustedReleaseURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/cgl-sd/weekflow/releases/tag/")
            && url.query == nil
            && url.fragment == nil
    }
}

private struct LatestRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

enum WeekflowAppVersion {
    static var current: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppUpdateService.versionComponents(value) != nil else {
            return nil
        }
        return value
    }
}
