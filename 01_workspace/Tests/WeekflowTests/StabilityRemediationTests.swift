import Carbon.HIToolbox
import Foundation
import Testing
@testable import Weekflow

@MainActor
@Test func globalDateShortcutsAreDisabledByDefaultAndFullyUnregistered() throws {
    let suite = "WeekflowGlobalShortcutTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let backend = FakeGlobalDateShortcutBackend()
    let service = GlobalDateShortcutService(defaults: defaults, backend: backend)

    service.refresh()

    #expect(backend.installations.isEmpty)
    #expect(backend.uninstallCount == 1)
    #expect(defaults.string(forKey: GlobalDateShortcutPreferences.stateKey) == "disabled")
}

@MainActor
@Test func globalDateShortcutsRegisterRefreshAndShutdownAsOneCompleteSet() throws {
    let suite = "WeekflowGlobalShortcutTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: GlobalDateShortcutPreferences.enabledKey)
    let backend = FakeGlobalDateShortcutBackend()
    let service = GlobalDateShortcutService(defaults: defaults, backend: backend)

    service.refresh()
    service.refresh()
    service.shutdown()

    #expect(backend.installations.count == 2)
    #expect(backend.installations.allSatisfy { $0.count == 3 })
    #expect(backend.installations.flatMap { $0 }.allSatisfy {
        $0.modifiers & UInt32(cmdKey) != 0 && $0.modifiers & UInt32(optionKey) != 0
    })
    #expect(backend.uninstallCount == 3)
    #expect(defaults.string(forKey: GlobalDateShortcutPreferences.stateKey) == "disabled")
}

@MainActor
@Test func globalDateShortcutConflictIsVisibleAndLeavesNoRegistration() throws {
    let suite = "WeekflowGlobalShortcutTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: GlobalDateShortcutPreferences.enabledKey)
    let backend = FakeGlobalDateShortcutBackend()
    backend.installError = GlobalDateShortcutError.registration(actionID: 2, status: OSStatus(eventHotKeyExistsErr))
    let service = GlobalDateShortcutService(defaults: defaults, backend: backend)

    service.refresh()

    #expect(backend.uninstallCount == 2)
    #expect(defaults.string(forKey: GlobalDateShortcutPreferences.stateKey) == "failed")
    #expect(defaults.string(forKey: GlobalDateShortcutPreferences.errorKey)?.contains("占用") == true)
}

@MainActor
@Test func compactCodecRejectsEmptyUnknownAndTruncatedPayloads() {
    #expect(throws: CompactDataCodecError.self) { try CompactDataCodec.decode(Data()) }
    #expect(throws: CompactDataCodecError.self) { try CompactDataCodec.decode(Data([0])) }
    #expect(throws: CompactDataCodecError.self) { try CompactDataCodec.decode(Data([1])) }
    #expect(throws: CompactDataCodecError.self) { try CompactDataCodec.decode(Data([99, 1, 2])) }
    #expect(throws: CompactDataCodecError.self) { try CompactDataCodec.decode(Data([0x57, 1])) }
}

@MainActor
@Test func compactCodecRejectsUnsafeDeclaredSizesWithoutAllocating() {
    #expect(throws: CompactDataCodecError.self) {
        try CompactDataCodec.decode(legacyCompressedHeader(size: 1_000_000_000_000, body: [1]))
    }
    #expect(throws: CompactDataCodecError.self) {
        try CompactDataCodec.decode(legacyCompressedHeader(size: UInt64.max, body: [1]))
    }
}

@MainActor
@Test func compactCodecRejectsEmptyMismatchAndCorruption() throws {
    #expect(throws: CompactDataCodecError.self) {
        try CompactDataCodec.decode(legacyCompressedHeader(size: 20, body: []))
    }
    #expect(throws: CompactDataCodecError.self) {
        try CompactDataCodec.decode(legacyCompressedHeader(size: 20, body: [1, 2, 3]))
    }

    let original = Data(repeating: 0x41, count: 4_096)
    var corrupted = CompactDataCodec.encode(original)
    corrupted[corrupted.index(before: corrupted.endIndex)] ^= 0xff
    #expect(throws: CompactDataCodecError.self) { try CompactDataCodec.decode(corrupted) }
}

@MainActor
@Test func compactCodecRejectsDeterministicRandomCorruptionCorpus() throws {
    let original = Data((0..<16_384).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    let encoded = CompactDataCodec.encode(original)
    for seed in 0..<128 {
        var damaged = encoded
        let index = damaged.index(
            damaged.startIndex,
            offsetBy: (seed &* 977 + 3) % damaged.count
        )
        damaged[index] ^= UInt8(truncatingIfNeeded: seed + 1)
        #expect(throws: CompactDataCodecError.self) {
            try CompactDataCodec.decode(damaged)
        }
    }
}

@MainActor
@Test func compactCodecRoundTripsRawCompressedAndLegacyPayloads() throws {
    let raw = Data("small payload".utf8)
    let compressed = Data(repeating: 0x41, count: 32_768)

    #expect(try CompactDataCodec.decode(CompactDataCodec.encode(raw)) == raw)
    #expect(try CompactDataCodec.decode(CompactDataCodec.encode(compressed)) == compressed)
    #expect(try CompactDataCodec.decode(Data([0]) + raw) == raw)
}

private func legacyCompressedHeader(size: UInt64, body: [UInt8]) -> Data {
    var littleEndianSize = size.littleEndian
    var data = Data([1])
    withUnsafeBytes(of: &littleEndianSize) { data.append(contentsOf: $0) }
    data.append(contentsOf: body)
    return data
}

private final class FakeGlobalDateShortcutBackend: GlobalDateShortcutBackend {
    var installations: [[GlobalDateShortcutDescriptor]] = []
    var uninstallCount = 0
    var installError: Error?

    func install(
        descriptors: [GlobalDateShortcutDescriptor],
        onAction: @escaping (UInt32) -> Void
    ) throws {
        installations.append(descriptors)
        if let installError { throw installError }
    }

    func uninstall() {
        uninstallCount += 1
    }
}

@MainActor
@Test func localDayKeyRemainsStableAcrossExtremeTimeZonesAndDST() throws {
    var shanghai = Calendar(identifier: .gregorian)
    shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    var losAngeles = Calendar(identifier: .gregorian)
    losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var utcPlusFourteen = Calendar(identifier: .gregorian)
    utcPlusFourteen.timeZone = try #require(TimeZone(secondsFromGMT: 14 * 3_600))
    var utcMinusTwelve = Calendar(identifier: .gregorian)
    utcMinusTwelve.timeZone = try #require(TimeZone(secondsFromGMT: -12 * 3_600))

    for day in [
        LocalDay(year: 2026, month: 3, day: 8),
        LocalDay(year: 2026, month: 11, day: 1),
        LocalDay(year: 2026, month: 7, day: 22)
    ] {
        #expect(day.persistenceKey == LocalDay(
            try #require(day.date(in: shanghai)),
            calendar: shanghai
        ).persistenceKey)
        #expect(day.persistenceKey == LocalDay(
            try #require(day.date(in: losAngeles)),
            calendar: losAngeles
        ).persistenceKey)
        #expect(day.persistenceKey == LocalDay(
            try #require(day.date(in: utcPlusFourteen)),
            calendar: utcPlusFourteen
        ).persistenceKey)
        #expect(day.persistenceKey == LocalDay(
            try #require(day.date(in: utcMinusTwelve)),
            calendar: utcMinusTwelve
        ).persistenceKey)
    }
}

@MainActor
@Test func businessDatesSurviveCrossTimeZoneSaveRestartAndRewrite() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowCrossZone-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let storeURL = folder.appendingPathComponent("Weekflow.store")
    let shanghai = try calendar(in: "Asia/Shanghai")
    let losAngeles = try calendar(in: "America/Los_Angeles")
    let planned = LocalDay(year: 2026, month: 3, day: 8)
    let assigned = LocalDay(year: 2026, month: 11, day: 1)
    var task = WeekTask(title: "跨时区", estimatedMinutes: 30)
    task.plannedDay = planned
    task.assignedDays = [assigned]
    task.dueDay = assigned
    task.executionWeekStartDay = LocalDay(year: 2026, month: 10, day: 26)
    task.completionCredits = [CompletionCredit(
        date: try #require(planned.date(in: shanghai)),
        reason: .actualTimeLogged,
        minutes: 1,
        seconds: 1
    )]
    var goal = WeeklyGoal(
        title: "日期不漂移",
        outcome: "LocalDay",
        startDate: try #require(planned.date(in: shanghai)),
        endDate: try #require(assigned.date(in: shanghai)),
        tasks: [task]
    )
    goal.startDay = planned
    goal.endDay = assigned

    let goalToSave = goal
    try withPersistenceActor(url: storeURL, calendar: shanghai) { repository in
        try repository.saveGoals([goalToSave], kind: .userEdit)
    }
    let loaded = try withPersistenceActor(url: storeURL, calendar: losAngeles) {
        try #require($0.loadGoals()?.first)
    }
    #expect(loaded.startDay == planned)
    #expect(loaded.endDay == assigned)
    #expect(loaded.tasks[0].plannedDay == planned)
    #expect(loaded.tasks[0].assignedDays == [assigned])
    #expect(loaded.tasks[0].completionCredits[0].day == planned)
    var modifiedLoaded = loaded
    modifiedLoaded.title = "洛杉矶改写"
    let loadedToSave = modifiedLoaded
    try withPersistenceActor(url: storeURL, calendar: losAngeles) {
        try $0.saveGoals([loadedToSave], kind: .userEdit)
    }
    let verified = try withPersistenceActor(url: storeURL, calendar: shanghai) {
        try #require($0.loadGoals()?.first)
    }
    #expect(verified.startDay == planned)
    #expect(verified.endDay == assigned)
    #expect(verified.tasks[0].assignedDays == [assigned])
}

@MainActor
@Test func automaticDistributionUndoMatchesCanonicalDayAcrossTimeZones() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowCrossZoneUndo-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("Weekflow.store")
    let plusFourteen = try calendar(secondsFromGMT: 14 * 3_600)
    let minusTwelve = try calendar(secondsFromGMT: -12 * 3_600)
    let day = LocalDay(year: 2026, month: 1, day: 1)
    var task = WeekTask(title: "自动分配", estimatedMinutes: 30)
    task.assignedDays = [day]
    let goal = WeeklyGoal(
        title: "极端时区",
        outcome: "撤销",
        startDate: try #require(day.date(in: plusFourteen)),
        endDate: try #require(day.date(in: plusFourteen)),
        tasks: [task]
    )
    let transactionID = UUID()
    try withPersistenceActor(url: url, calendar: plusFourteen) {
        try $0.saveGoals([goal], kind: .automaticDistribution(transactionID: transactionID))
    }
    let loaded = try withPersistenceActor(url: url, calendar: minusTwelve) {
        try #require($0.loadGoals()?.first)
    }
    var modifiedLoaded = loaded
    modifiedLoaded.tasks[0].assignedDays = []
    let loadedToSave = modifiedLoaded
    try withPersistenceActor(url: url, calendar: minusTwelve) {
        try $0.saveGoals([loadedToSave], kind: .undoAutomaticDistribution(transactionID: transactionID))
    }
    let verified = try withPersistenceActor(url: url, calendar: plusFourteen) {
        try #require($0.loadGoals()?.first)
    }
    #expect(verified.tasks[0].assignedDays.isEmpty)
}

@MainActor
@Test func dailySummaryAndWeekStartStayCanonicalAcrossDSTAndRuntimeZoneChange() throws {
    let shanghai = try calendar(in: "Asia/Shanghai")
    let losAngeles = try calendar(in: "America/Los_Angeles")
    let service = MutableBusinessCalendar(calendar: shanghai)
    let day = LocalDay(year: 2026, month: 3, day: 8)
    let summary = DailySummary(
        date: try #require(day.date(in: shanghai)),
        content: "DST 开始日"
    )
    #expect(summary.day == day)
    #expect(service.startOfWeek(containing: day) == LocalDay(year: 2026, month: 3, day: 2))
    service.calendar = losAngeles
    #expect(summary.day == day)
    #expect(service.startOfWeek(containing: day) == LocalDay(year: 2026, month: 3, day: 2))
    #expect(service.day(containing: service.date(for: day)) == day)
}

private final class MutableBusinessCalendar: BusinessCalendarProviding, @unchecked Sendable {
    var calendar: Calendar
    init(calendar: Calendar) { self.calendar = calendar }
    func day(containing date: Date) -> LocalDay { LocalDay(date, calendar: calendar) }
    func date(for day: LocalDay) -> Date { day.date(in: calendar) ?? .distantPast }
    func date(for time: LocalTime, on day: LocalDay) -> Date { time.date(on: day, calendar: calendar) ?? date(for: day) }
    func addingDays(_ value: Int, to day: LocalDay) -> LocalDay {
        self.day(containing: calendar.date(byAdding: .day, value: value, to: date(for: day)) ?? date(for: day))
    }
    func addingMonths(_ value: Int, to day: LocalDay) -> LocalDay {
        self.day(containing: calendar.date(byAdding: .month, value: value, to: date(for: day)) ?? date(for: day))
    }
    func startOfWeek(containing day: LocalDay) -> LocalDay {
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date(for: day))
        components.weekday = 2
        return self.day(containing: calendar.date(from: components) ?? date(for: day))
    }
}

private func calendar(in identifier: String) throws -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = try #require(TimeZone(identifier: identifier))
    value.firstWeekday = 2
    return value
}

private func calendar(secondsFromGMT: Int) throws -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = try #require(TimeZone(secondsFromGMT: secondsFromGMT))
    value.firstWeekday = 2
    return value
}

private func withPersistenceActor<Result: Sendable>(
    url: URL,
    calendar: Calendar,
    operation: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result
) throws -> Result {
    try PersistenceActorBridge.run(
        on: PersistenceActor(storeURL: url, calendar: calendar),
        operation
    )
}

@MainActor
@Test func commandRouterTargetsOnlyTheActiveWindow() throws {
    let router = CommandRouter()
    let first = AppCoordinator(sceneID: UUID(), commands: router)
    let second = AppCoordinator(sceneID: UUID(), commands: router)
    first.activate()
    router.send(.addTask)
    let firstCommand = try #require(router.latest)
    #expect(first.accepts(firstCommand))
    #expect(!second.accepts(firstCommand))

    second.activate()
    router.send(.jumpToNextDay)
    let secondCommand = try #require(router.latest)
    #expect(!first.accepts(secondCommand))
    #expect(second.accepts(secondCommand))
}

@MainActor
@Test func goalServiceOwnsCanonicalFieldsAndBuildsReadOnlyProjections() throws {
    let day = SystemBusinessCalendar.current.date(for: LocalDay(year: 2026, month: 7, day: 20))
    let item = GoalSubgoal(title: "唯一标题", detail: "唯一说明", isCompleted: false)
    let stale = WeekTask(
        title: "陈旧副本",
        dueDate: day,
        estimatedMinutes: 30,
        description: "陈旧说明",
        subgoalID: item.id,
        channelID: "stale",
        sourceType: .weeklyObjective
    )
    let goal = WeeklyGoal(
        title: "目标",
        outcome: "结果",
        startDate: day,
        endDate: day,
        channelID: "work",
        subgoals: [item],
        tasks: [stale]
    )
    let service = GoalService()
    let normalized = service.project(goal)
    let projectedTask = try #require(normalized.tasks.first)
    #expect(projectedTask.title == item.title)
    #expect(projectedTask.description == item.detail)
    #expect(projectedTask.channelID == goal.channelID)
    let projection = service.weeklyPlanningProjection(normalized)
    #expect(projection.items.first?.title == item.title)
    #expect(projection.items.first?.detail == item.detail)
    #expect(projection.items.first?.channelID == goal.channelID)
}

@MainActor
@Test func internalFeatureCommandsDoNotUseNotificationCenterBus() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let commands = try String(
        contentsOf: root.appendingPathComponent("Sources/Weekflow/Support/WeekflowCommands.swift"),
        encoding: .utf8
    )
    let content = try String(
        contentsOf: root.appendingPathComponent("Sources/Weekflow/Views/ContentView.swift"),
        encoding: .utf8
    )
    #expect(!commands.contains("NotificationCenter.default.post"))
    #expect(!content.contains("publisher(for: .weekflow"))
}

@MainActor
@Test func applicationLifecycleCheckpointsTimersForSleepWakeAndTermination() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/Weekflow/App/WeekflowApp.swift"),
        encoding: .utf8
    )
    #expect(source.contains("NSWorkspace.willSleepNotification"))
    #expect(source.contains("NSWorkspace.didWakeNotification"))
    #expect(source.contains("func applicationWillTerminate"))
    #expect(source.contains("checkpointActiveTimer?()"))
    #expect(source.contains("globalDateShortcuts.shutdown()"))
}

@MainActor
@Test func repeatedOneSecondTaskPausesAccumulateSecondsWithoutMinuteInflation() throws {
    let fixture = WeekflowDevelopmentFixture.stageOne(referenceDate: .now)
    let store = WeekflowStore(developmentFixture: fixture)
    let entry = try #require(store.activeTasks.first)
    let initialSeconds = entry.task.actualSeconds
    var now = Date(timeIntervalSinceReferenceDate: 900_000_000)

    for _ in 0..<100 {
        store.startTaskTimer(goalID: entry.goal.id, taskID: entry.task.id, now: now)
        now = now.addingTimeInterval(1)
        store.pauseTaskTimer(goalID: entry.goal.id, taskID: entry.task.id, now: now)
    }

    let updated = try #require(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.first(where: { $0.id == entry.task.id }))
    #expect(updated.actualSeconds == initialSeconds + 100)
    #expect(updated.actualMinutes == DurationDisplay.minutes(for: initialSeconds + 100))
}

@MainActor
@Test func focusPauseRemaindersAreWrittenAsExactSeconds() {
    let defaults = UserDefaults(suiteName: "WeekflowFocusSecondTests-\(UUID().uuidString)")!
    let timer = FocusTimerService(
        defaults: defaults,
        notificationScheduler: NoopFocusNotificationScheduler()
    )
    var recordedSeconds = 0
    timer.configureFocusWriter { _, seconds, _ in recordedSeconds += seconds }

    timer.start(now: .now)
    timer.advance(by: 30)
    timer.pause()
    timer.start(now: .now)
    timer.advance(by: 30)
    timer.pause()

    #expect(recordedSeconds == 60)
}

@MainActor
private final class NoopFocusNotificationScheduler: FocusNotificationScheduling {
    func requestPermission() {}
    func sendCompletion(mode: FocusMode, minutes: Int) {}
}

@MainActor
@Test func deniedNotificationPermissionIsVisibleWithoutStoppingTheTimer() {
    let scheduler = DeniedFocusNotificationScheduler()
    let timer = FocusTimerService(
        defaults: UserDefaults(suiteName: "WeekflowDeniedNotifications-\(UUID())")!,
        notificationScheduler: scheduler
    )
    timer.start()
    #expect(timer.isRunning)
    #expect(timer.notificationPermissionIssue?.contains("通知权限") == true)
    timer.cancel()
}

@MainActor
private final class DeniedFocusNotificationScheduler: FocusNotificationScheduling {
    func requestPermission() {}
    func requestPermission(completion: @escaping @MainActor (Bool) -> Void) { completion(false) }
    func sendCompletion(mode: FocusMode, minutes: Int) {}
}

@MainActor
@Test func activeTaskTimerRestoresAcrossStoreRestartAndClearsAfterPause() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowActiveTimerTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = LocalStorage(baseDirectory: folder)
    var store: WeekflowStore? = WeekflowStore(storage: storage)
    store?.synchronousPersistence = true
    let goalID = try #require(store?.addGoal(title: "恢复计时", outcome: "稳定性", endDate: .now))
    let taskID = try #require(store?.goals.first(where: { $0.id == goalID })?.tasks.first?.id)
    let startedAt = Date.now.addingTimeInterval(-61)
    store?.startTaskTimer(goalID: goalID, taskID: taskID, now: startedAt)
    store = nil

    let restored = WeekflowStore(storage: storage)
    restored.synchronousPersistence = true
    #expect(restored.activeTaskTimer?.goalID == goalID)
    #expect(restored.activeTaskTimer?.taskID == taskID)
    restored.pauseTaskTimer(goalID: goalID, taskID: taskID, now: startedAt.addingTimeInterval(61))

    let afterPause = WeekflowStore(storage: storage)
    #expect(afterPause.activeTaskTimer == nil)
    let task = try #require(afterPause.goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.id == taskID }))
    #expect(task.actualSeconds == 61)
}

@MainActor
@Test func interruptedLongTimerRequiresExplicitRecoveryAndOrphansAreRepaired() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowInterruptedTimer-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = LocalStorage(baseDirectory: folder)
    var store: WeekflowStore? = WeekflowStore(storage: storage)
    store?.synchronousPersistence = true
    let goalID = try #require(store?.addGoal(title: "异常计时", outcome: "恢复", endDate: .now))
    let taskID = try #require(store?.goals.first(where: { $0.id == goalID })?.tasks.first?.id)
    store?.startTaskTimer(goalID: goalID, taskID: taskID, now: .now.addingTimeInterval(-2 * 86_400))
    store = nil

    let interrupted = WeekflowStore(storage: storage)
    #expect(interrupted.activeTaskTimer == nil)
    #expect(interrupted.pendingTimerRecovery?.session.taskID == taskID)
    interrupted.resolveInterruptedTimer(includeElapsedTime: false)
    #expect(interrupted.pendingTimerRecovery == nil)
    #expect(WeekflowStore(storage: storage).activeTaskTimer == nil)

    try storage.saveActiveTimerSession(TaskTimerSession(
        goalID: UUID(),
        taskID: UUID(),
        startedAt: .now,
        baseActualSeconds: 0,
        lastCheckpointAt: .now
    ))
    let repaired = WeekflowStore(storage: storage)
    #expect(repaired.activeTaskTimer == nil)
    #expect(repaired.pendingTimerRecovery == nil)
    #expect(try storage.loadActiveTimerSession() == nil)
}

@MainActor
@Test func exactSecondAccumulatorHandlesMinuteBoundariesAndMidnight() throws {
    let fixture = WeekflowDevelopmentFixture.stageOne(referenceDate: .now)
    let entry = try #require(fixture.goals.first.flatMap { goal in
        goal.tasks.first.map { (goal.id, $0.id, $0.actualSeconds) }
    })
    for chunks in [[30, 30], [59, 1], [61]] {
        let store = WeekflowStore(developmentFixture: fixture)
        var instant = Date(timeIntervalSince1970: 1_767_225_599) // 23:59:59 UTC
        for seconds in chunks {
            store.startTaskTimer(goalID: entry.0, taskID: entry.1, now: instant)
            instant = instant.addingTimeInterval(TimeInterval(seconds))
            store.pauseTaskTimer(goalID: entry.0, taskID: entry.1, now: instant)
        }
        let actual = try #require(store.goals.first?.tasks.first?.actualSeconds)
        #expect(actual == entry.2 + chunks.reduce(0, +))
    }
}

// MARK: - P2-4: Fixed-calendar timezone / DST parameterized coverage

/// P2-4 fix: verifies day-boundary stability using FIXED calendars and
/// `calendar.date(byAdding:.day:)` arithmetic instead of `Calendar.current`
/// and a hard-coded 86,400-second day (which breaks across DST). Covers the
/// timezones called out in review, including Europe/Berlin DST start.
@Test("Day boundary stays stable across timezones and DST", arguments: [
    "Asia/Shanghai",
    "America/Los_Angeles",
    "Pacific/Kiritimati",
    "Pacific/Pago_Pago",
    "Europe/Berlin"
])
func dayBoundaryStableAcrossTimezonesAndDST(timeZoneID: String) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: timeZoneID))
    let business = BusinessCalendar(calendar: calendar)
    // Anchor at local noon to avoid midnight-edge ambiguity. 2026-03-28 sits
    // just before the Europe/Berlin DST start (last Sunday of March).
    let anchor = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 12)))
    let startDay = business.day(containing: anchor)

    for offset in 1...7 {
        let advanced = try #require(calendar.date(byAdding: .day, value: offset, to: anchor))
        let dayFromInstant = business.day(containing: advanced)
        let dayFromArithmetic = business.addingDays(offset, to: startDay)
        #expect(dayFromInstant == dayFromArithmetic, "tz=\(timeZoneID) offset=\(offset)")
        // Round-trip Date -> LocalDay -> Date preserves the local day.
        let roundTrip = business.day(containing: business.date(for: dayFromInstant))
        #expect(roundTrip == dayFromInstant, "tz=\(timeZoneID) offset=\(offset)")
    }
}

/// P2-4 fix: a 23:30 local instant must stay on the same LocalDay even when a
/// DST shift changes the UTC offset, and adding one calendar day must land on
/// the next LocalDay (not skip or repeat due to a 23/25-hour day).
@Test("LocalDay honours calendar days not fixed seconds around DST", arguments: [
    "Europe/Berlin",
    "America/Los_Angeles"
])
func localDayHonoursCalendarDaysAroundDST(timeZoneID: String) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: timeZoneID))
    let business = BusinessCalendar(calendar: calendar)
    let anchor = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 23, minute: 30)))
    let day = business.day(containing: anchor)
    #expect(day == LocalDay(year: 2026, month: 3, day: 28))
    let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: anchor))
    #expect(business.day(containing: nextDay) == LocalDay(year: 2026, month: 3, day: 29))
}

// MARK: - P1-4: Strict LocalDay / LocalTime validation

@Test func localDayRejectsImpossibleComponents() {
    #expect(LocalDay(validatingYear: 2026, month: 99, day: -10) == nil)
    #expect(LocalDay(validatingYear: 2026, month: 2, day: 30) == nil)
    #expect(LocalDay(validatingYear: 2026, month: 7, day: 22) != nil)
}

@Test func localTimeStrictInitRejectsOutOfRangeInsteadOfClamping() {
    #expect(LocalTime(validatingMinutesSinceMidnight: -100) == nil)
    #expect(LocalTime(validatingMinutesSinceMidnight: 100_000) == nil)
    #expect(LocalTime(validatingMinutesSinceMidnight: 0)?.minutesSinceMidnight == 0)
    #expect(LocalTime(validatingMinutesSinceMidnight: 23 * 60 + 59)?.minutesSinceMidnight == 23 * 60 + 59)
}

@Test func systemBusinessCalendarOverrideIsHonouredByModelLayer() throws {
    var fixed = Calendar(identifier: .gregorian)
    fixed.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    SystemBusinessCalendar.override = BusinessCalendar(calendar: fixed)
    defer { SystemBusinessCalendar.override = nil }
    // The model-layer global calendar must now match the injected override,
    // closing the gap where tests could not reach the model's global calls.
    #expect(SystemBusinessCalendar.current.calendar.timeZone.identifier == "Asia/Shanghai")
}
