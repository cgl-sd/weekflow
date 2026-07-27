import Foundation
import Testing
@testable import Weekflow

struct AppUpdateServiceTests {
    @Test func reportsNewerRelease() async throws {
        let service = makeService(tags: ["v0.7.1", "v0.8.0"])
        let result = try await service.check(currentVersion: "0.7.1")

        #expect(result.isUpdateAvailable)
        #expect(result.latestVersion == "v0.8.0")
    }

    @Test func unifiedReleaseFeedIncludesGitHubPrereleasesAndSelectsHighestVersion() async throws {
        let service = makeService(tags: ["v0.7.1", "v1.0.1", "v1.0.0"])
        let result = try await service.check(currentVersion: "1.0.0")

        #expect(result.isUpdateAvailable)
        #expect(result.latestVersion == "v1.0.1")
        #expect(result.releaseURL.absoluteString == "https://github.com/cgl-sd/weekflow/releases/tag/v1.0.1")
    }

    @Test func treatsEquivalentVersionsAsCurrent() async throws {
        let service = makeService(tags: ["v0.7.1"])
        let result = try await service.check(currentVersion: "0.7.1")

        #expect(!result.isUpdateAvailable)
        #expect(AppUpdateService.compareVersions("1.2", "1.2.0") == .orderedSame)
    }

    @Test func semanticVersionPrereleasesUseReleaseOrdering() {
        #expect(AppUpdateService.compareVersions("1.0.0-beta.2", "1.0.0-beta.11") == .orderedAscending)
        #expect(AppUpdateService.compareVersions("1.0.0-rc.1", "1.0.0") == .orderedAscending)
        #expect(AppUpdateService.compareVersions("1.0.0", "1.0.0-rc.1") == .orderedDescending)
        #expect(AppUpdateService.compareVersions("v1.2.3+build.8", "1.2.3+build.9") == .orderedSame)
        #expect(AppUpdateService.versionComponents("1.0.0-01") == nil)
    }

    @Test func rejectsUntrustedReleaseURL() async {
        let service = makeService(releaseURLs: [
            "https://example.com/cgl-sd/weekflow/releases/tag/v0.8.0"
        ])

        await #expect(throws: AppUpdateError.invalidRelease) {
            try await service.check(currentVersion: "0.7.1")
        }
    }

    @Test func rejectsOversizedResponse() async {
        let service = AppUpdateService { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "999999"]
            )!
            return (Data("{}".utf8), response)
        }

        await #expect(throws: AppUpdateError.responseTooLarge) {
            try await service.check(currentVersion: "0.7.1")
        }
    }

    @Test func streamingLoaderStopsAtTheResponseLimit() async throws {
        let validBytes = AsyncStream<UInt8> { continuation in
            for _ in 0..<AppUpdateService.maximumResponseBytes {
                continuation.yield(0x41)
            }
            continuation.finish()
        }
        let valid = try await AppUpdateService.collectBoundedBytes(validBytes)
        #expect(valid.count == AppUpdateService.maximumResponseBytes)

        let oversizedBytes = AsyncStream<UInt8> { continuation in
            for _ in 0...AppUpdateService.maximumResponseBytes {
                continuation.yield(0x41)
            }
            continuation.finish()
        }
        await #expect(throws: AppUpdateError.responseTooLarge) {
            _ = try await AppUpdateService.collectBoundedBytes(oversizedBytes)
        }
    }

    @Test func rejectsHTTPFailure() async {
        let service = AppUpdateService { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        await #expect(throws: AppUpdateError.requestFailed(503)) {
            try await service.check(currentVersion: "0.7.1")
        }
    }

    @Test func rejectsUntrustedFeedRedirect() async {
        let service = AppUpdateService { request in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com/releases.atom")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(Self.feed(releaseURLs: [
                "https://github.com/cgl-sd/weekflow/releases/tag/v1.0.1"
            ]).utf8), response)
        }

        await #expect(throws: AppUpdateError.invalidResponse) {
            try await service.check(currentVersion: "1.0.0")
        }
    }

    private func makeService(
        tags: [String]
    ) -> AppUpdateService {
        makeService(releaseURLs: tags.map {
            "https://github.com/cgl-sd/weekflow/releases/tag/\($0)"
        })
    }

    private func makeService(releaseURLs: [String]) -> AppUpdateService {
        AppUpdateService { request in
            #expect(request.url == AppUpdateService.releaseFeedEndpoint)
            #expect(request.httpMethod == "GET")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/atom+xml"]
            )!
            return (Data(Self.feed(releaseURLs: releaseURLs).utf8), response)
        }
    }

    private static func feed(releaseURLs: [String]) -> String {
        let entries = releaseURLs.map { url in
            "<entry><link rel=\"alternate\" href=\"\(url)\"/></entry>"
        }.joined()
        return "<?xml version=\"1.0\"?><feed>\(entries)</feed>"
    }
}
