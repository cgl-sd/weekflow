import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test("Marketing fixture and deterministic 2× website snapshots")
func marketingSiteSnapshots() throws {
    let calendar = marketingSnapshotCalendar()
    let referenceDate = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 12))
    )
    let fixture = WeekflowDevelopmentFixture.marketing(
        referenceDate: referenceDate,
        calendar: calendar
    )

    #expect(fixture.identifier == WeekflowDevelopmentFixture.marketingIdentifier)
    #expect(fixture.goals.count == 2)
    #expect(fixture.goals.allSatisfy { !$0.displayableSubgoals.isEmpty })
    #expect(Set(fixture.goals.flatMap(\.tasks).map(\.status)).isSuperset(of: [
        TaskStatus.completed,
        TaskStatus.inProgress,
        TaskStatus.planned
    ]))
    #expect(Set(fixture.goals.flatMap(\.tasks).compactMap(\.channelID)).count >= 4)
    #expect(fixture.focusRecords.count == 2)
    #expect(fixture.dailySummaries.count == 2)

    let coveredDays = Set(fixture.goals.flatMap(\.tasks).compactMap(\.plannedDay))
    let tuesday = LocalDay(referenceDate, calendar: calendar)
    let wednesdayDate = try #require(calendar.date(byAdding: .day, value: 1, to: referenceDate))
    let thursdayDate = try #require(calendar.date(byAdding: .day, value: 2, to: referenceDate))
    #expect(coveredDays.contains(tuesday))
    #expect(coveredDays.contains(LocalDay(wednesdayDate, calendar: calendar)))
    #expect(coveredDays.contains(LocalDay(thursdayDate, calendar: calendar)))

    let validationRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
        "WeekflowMarketingFixtureValidation-\(UUID().uuidString)",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: validationRoot) }
    let validationStore = WeekflowStore(
        storage: LocalStorage(baseDirectory: validationRoot),
        developmentFixture: fixture,
        businessCalendar: BusinessCalendar(calendar: calendar)
    )
    #expect(validationStore.focusRecords == fixture.focusRecords)
    #expect(validationStore.dailySummaries == fixture.dailySummaries)
    #expect(validationStore.tasks(on: referenceDate).count == 5)
    #expect(validationStore.tasks(on: wednesdayDate).count == 2)
    #expect(validationStore.tasks(on: thursdayDate).count == 2)

    guard let outputPath = ProcessInfo.processInfo.environment[
        "WEEKFLOW_MARKETING_SNAPSHOT_DIR"
    ], !outputPath.isEmpty else { return }

    let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )

    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
        "WeekflowMarketingSnapshots-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let defaultsName = "WeekflowMarketingSnapshots.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defaults.removePersistentDomain(forName: defaultsName)
    defer { defaults.removePersistentDomain(forName: defaultsName) }

    let size = NSSize(width: 1_200, height: 780)
    let destinations: [(name: String, destination: AppDestination, dailyPlanningStep: Int)] = [
        ("weekflow-home", .home, 0),
        ("weekflow-weekly-planning", .weeklyPlanning, 0),
        ("weekflow-daily-planning", .dailyPlanning, 2),
        ("weekflow-focus", .focus, 0),
        ("weekflow-daily-review", .dailyShutdown, 0),
        ("weekflow-weekly-review", .weeklyReview, 0)
    ]

    for (index, destination) in destinations.enumerated() {
        let store = WeekflowStore(
            storage: LocalStorage(
                baseDirectory: temporaryRoot.appendingPathComponent(
                    "store-\(index)",
                    isDirectory: true
                )
            ),
            developmentFixture: fixture,
            legacyPreferences: defaults,
            businessCalendar: BusinessCalendar(calendar: calendar)
        )
        #expect(store.focusRecords == fixture.focusRecords)
        #expect(store.dailySummaries == fixture.dailySummaries)

        let timer = FocusTimerService(
            defaults: defaults,
            notificationScheduler: MarketingSnapshotNotificationScheduler()
        )
        timer.select(.study)
        timer.updateCurrentDurationMinutes(50)

        let view = ContentView(
            store: store,
            focusTimer: timer,
            initialDestination: destination.destination,
            referenceDate: referenceDate,
            initialDailyPlanningStep: destination.dailyPlanningStep
        )
        .environment(\.businessCalendar, store.businessCalendar)
        .defaultAppStorage(defaults)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)

        try writeMarketingSnapshot(
            view,
            size: size,
            to: outputDirectory.appendingPathComponent("\(destination.name).png")
        )
    }
}

@MainActor
private final class MarketingSnapshotNotificationScheduler: FocusNotificationScheduling {
    func requestPermission() {}
    func sendCompletion(modeTitle: String, minutes: Int) {}
}

@MainActor
private func writeMarketingSnapshot<V: View>(
    _ rootView: V,
    size: NSSize,
    to outputURL: URL
) throws {
    let hostingView = NSHostingView(rootView: rootView)
    hostingView.frame = NSRect(origin: .zero, size: size)
    hostingView.wantsLayer = true

    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.contentView = hostingView

    hostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()

    let scale = 2
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * scale,
        pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw MarketingSnapshotError.bitmapAllocationFailed
    }
    bitmap.size = size
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    guard bitmap.pixelsWide == Int(size.width) * scale,
          bitmap.pixelsHigh == Int(size.height) * scale,
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw MarketingSnapshotError.pngEncodingFailed
    }
    try png.write(to: outputURL, options: .atomic)
    window.contentView = nil
    window.close()
}

private func marketingSnapshotCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "zh_CN")
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

private enum MarketingSnapshotError: Error {
    case bitmapAllocationFailed
    case pngEncodingFailed
}
