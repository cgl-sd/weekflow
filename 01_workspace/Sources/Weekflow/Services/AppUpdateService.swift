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

    static let releaseFeedEndpoint = URL(
        string: "https://github.com/cgl-sd/weekflow/releases.atom"
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
            url: Self.releaseFeedEndpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 12
        )
        request.httpMethod = "GET"
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        request.setValue("Weekflow-Update-Checker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await load(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw AppUpdateError.requestFailed(httpResponse.statusCode)
        }
        guard Self.isTrustedFeedResponse(httpResponse.url) else {
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

        let releases = ReleaseFeedParser.releases(in: data).filter {
            Self.versionComponents($0.tagName) != nil
                && Self.isTrustedReleaseURL($0.htmlURL)
        }
        let release = releases.max {
            Self.compareVersions($0.tagName, $1.tagName) == .orderedAscending
        }
        guard let release else { throw AppUpdateError.invalidRelease }

        return AppUpdateResult(
            currentVersion: currentVersion,
            latestVersion: release.tagName,
            releaseURL: release.htmlURL
        )
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        guard let left = SemanticVersion(lhs), let right = SemanticVersion(rhs) else {
            return .orderedSame
        }
        return left.compare(to: right)
    }

    static func versionComponents(_ version: String) -> [Int]? {
        SemanticVersion(version)?.core
    }

    private static func defaultLoader() -> Loader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        return { request in
            let (bytes, response) = try await session.bytes(for: request)
            let data = try await collectBoundedBytes(bytes)
            return (data, response)
        }
    }

    /// Collects a response incrementally and stops as soon as the configured
    /// ceiling is crossed. Checking `Data.count` only after `data(for:)` returns
    /// would allow an abnormal response to be fully buffered first.
    static func collectBoundedBytes<Bytes: AsyncSequence>(
        _ bytes: Bytes,
        maximumBytes: Int = maximumResponseBytes
    ) async throws -> Data where Bytes.Element == UInt8 {
        var data = Data()
        data.reserveCapacity(min(maximumBytes, 8 * 1_024))
        for try await byte in bytes {
            guard data.count < maximumBytes else {
                throw AppUpdateError.responseTooLarge
            }
            data.append(byte)
        }
        return data
    }

    private static func isTrustedFeedResponse(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "github.com"
            && url.path == "/cgl-sd/weekflow/releases.atom"
            && url.query == nil
            && url.fragment == nil
    }

    private static func isTrustedReleaseURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/cgl-sd/weekflow/releases/tag/")
            && url.query == nil
            && url.fragment == nil
    }
}

private struct SemanticVersion {
    let core: [Int]
    let prerelease: [String]

    init?(_ rawValue: String) {
        var normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("v") { normalized.removeFirst() }
        guard !normalized.isEmpty, normalized.count <= 64 else { return nil }

        let withoutBuild = normalized.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard !withoutBuild[0].isEmpty,
              withoutBuild.count == 1 || Self.validIdentifiers(String(withoutBuild[1]), allowLeadingZero: true)
        else { return nil }
        let versionAndPrerelease = withoutBuild[0].split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let coreParts = versionAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(coreParts.count) else { return nil }
        var parsedCore: [Int] = []
        for part in coreParts {
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  (part.count == 1 || part.first != "0"),
                  let value = Int(part),
                  value <= 999_999 else { return nil }
            parsedCore.append(value)
        }
        var parsedPrerelease: [String] = []
        if versionAndPrerelease.count == 2 {
            let value = String(versionAndPrerelease[1])
            guard Self.validIdentifiers(value, allowLeadingZero: false) else { return nil }
            parsedPrerelease = value.split(separator: ".").map(String.init)
        }
        core = parsedCore
        prerelease = parsedPrerelease
    }

    func compare(to other: SemanticVersion) -> ComparisonResult {
        let count = max(core.count, other.core.count)
        for index in 0..<count {
            let left = index < core.count ? core[index] : 0
            let right = index < other.core.count ? other.core[index] : 0
            if left != right { return left < right ? .orderedAscending : .orderedDescending }
        }
        if prerelease.isEmpty && other.prerelease.isEmpty { return .orderedSame }
        if prerelease.isEmpty { return .orderedDescending }
        if other.prerelease.isEmpty { return .orderedAscending }
        for (left, right) in zip(prerelease, other.prerelease) where left != right {
            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case let (.some(lhs), .some(rhs)):
                return lhs < rhs ? .orderedAscending : .orderedDescending
            case (.some, .none):
                return .orderedAscending
            case (.none, .some):
                return .orderedDescending
            case (.none, .none):
                return left < right ? .orderedAscending : .orderedDescending
            }
        }
        if prerelease.count == other.prerelease.count { return .orderedSame }
        return prerelease.count < other.prerelease.count ? .orderedAscending : .orderedDescending
    }

    private static func validIdentifiers(_ value: String, allowLeadingZero: Bool) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return false }
            return allowLeadingZero || !part.allSatisfy(\.isNumber) || part.count == 1 || part.first != "0"
        }
    }
}

private struct LatestRelease {
    let tagName: String
    let htmlURL: URL
}

private final class ReleaseFeedParser: NSObject, XMLParserDelegate {
    private var isInsideEntry = false
    private var entryURL: URL?
    private(set) var parsedReleases: [LatestRelease] = []

    static func releases(in data: Data) -> [LatestRelease] {
        let delegate = ReleaseFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { return [] }
        return delegate.parsedReleases
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "entry" {
            isInsideEntry = true
            entryURL = nil
        } else if isInsideEntry,
                  elementName == "link",
                  attributeDict["rel"] == "alternate",
                  let href = attributeDict["href"] {
            entryURL = URL(string: href)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "entry" else { return }
        if let entryURL,
           let tagName = entryURL.pathComponents.last,
           !tagName.isEmpty {
            parsedReleases.append(LatestRelease(tagName: tagName, htmlURL: entryURL))
        }
        isInsideEntry = false
        entryURL = nil
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
