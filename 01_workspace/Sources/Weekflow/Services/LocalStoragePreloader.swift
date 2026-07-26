import Foundation

enum LocalStoragePreloadKey: String, Hashable, Sendable, CaseIterable {
    case goals
    case plans
    case channels
    case calendarEvents
    case dailyPlanningStates
    case focusRecords
    case dailySummaries
    case activeTimer
    case automaticDistribution
    case payloadNormalization
}

struct LocalStoragePreload: @unchecked Sendable {
    var goals: [WeeklyGoal]? = nil
    var plans: [WeeklyPlan]? = nil
    var channels: [TaskChannel]? = nil
    var calendarEvents: [CalendarEvent]? = nil
    var dailyPlanningStates: [DailyPlanningState]? = nil
    var focusRecords: [FocusRecord]? = nil
    var dailySummaries: [DailySummary]? = nil
    var activeTimerSession: TaskTimerSession? = nil
    var pendingAutomaticDistributionChanges: [PersistedAutomaticDistributionChange] = []
    var failures: [LocalStoragePreloadKey: String] = [:]
    var consumableKeys: Set<LocalStoragePreloadKey> = []

    func throwIfFailed(_ key: LocalStoragePreloadKey) throws {
        if let message = failures[key] {
            throw LocalStoragePreloadError(key: key, message: message)
        }
    }
}

struct LocalStoragePreloadError: LocalizedError, Sendable {
    let key: LocalStoragePreloadKey
    let message: String
    var errorDescription: String? { message }
}

enum LocalStoragePreloadedValue<Value> {
    case unavailable
    case value(Value)
}

/// One-shot, thread-safe startup cache. Each value is consumed by the first
/// synchronous Store load, after which LocalStorage falls back to the live
/// database. This prevents a preloaded LocalStorage from returning stale startup
/// data during later reload/recovery operations.
final class LocalStoragePreloadCache: @unchecked Sendable {
    private let lock = NSLock()
    private let preload: LocalStoragePreload
    private var remaining: Set<LocalStoragePreloadKey>

    init(_ preload: LocalStoragePreload) {
        self.preload = preload
        remaining = preload.consumableKeys
    }

    func take<Value>(
        _ key: LocalStoragePreloadKey,
        _ keyPath: KeyPath<LocalStoragePreload, Value>
    ) throws -> LocalStoragePreloadedValue<Value> {
        lock.lock()
        defer { lock.unlock() }
        guard remaining.remove(key) != nil else { return .unavailable }
        try preload.throwIfFailed(key)
        return .value(preload[keyPath: keyPath])
    }

    func consume(_ key: LocalStoragePreloadKey) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard remaining.remove(key) != nil else { return false }
        try preload.throwIfFailed(key)
        return true
    }
}

enum LocalStoragePreloader {
    /// Performs all startup database work on a detached task. The returned
    /// LocalStorage copy shares the same PersistenceActor but serves the initial
    /// WeekflowStore reads from memory, keeping SwiftUI/AppKit startup responsive.
    static func preload(_ storage: LocalStorage) async -> LocalStorage {
        let preload = await Task.detached(priority: .userInitiated) {
            var result = LocalStoragePreload()

            do { result.goals = try await storage.loadAsync() } catch {
                result.failures[.goals] = error.localizedDescription
            }
            result.consumableKeys.insert(.goals)
            do { result.plans = try await storage.loadPlansAsync() } catch {
                result.failures[.plans] = error.localizedDescription
            }
            result.consumableKeys.insert(.plans)
            do { result.channels = try await storage.loadChannelsAsync() } catch {
                result.failures[.channels] = error.localizedDescription
            }
            result.consumableKeys.insert(.channels)
            do { result.calendarEvents = try await storage.loadCalendarEventsAsync() } catch {
                result.failures[.calendarEvents] = error.localizedDescription
            }
            result.consumableKeys.insert(.calendarEvents)
            do { result.dailyPlanningStates = try await storage.loadDailyPlanningStatesAsync() } catch {
                result.failures[.dailyPlanningStates] = error.localizedDescription
            }
            result.consumableKeys.insert(.dailyPlanningStates)
            do { result.focusRecords = try await storage.loadFocusRecordsAsync() } catch {
                result.failures[.focusRecords] = error.localizedDescription
            }
            result.consumableKeys.insert(.focusRecords)
            do { result.dailySummaries = try await storage.loadDailySummariesAsync() } catch {
                result.failures[.dailySummaries] = error.localizedDescription
            }
            result.consumableKeys.insert(.dailySummaries)
            do { result.activeTimerSession = try await storage.loadActiveTimerSessionAsync() } catch {
                result.failures[.activeTimer] = error.localizedDescription
            }
            result.consumableKeys.insert(.activeTimer)

            if let session = result.activeTimerSession,
                !(result.goals ?? []).contains(where: { goal in
                    goal.id == session.goalID && goal.tasks.contains(where: { $0.id == session.taskID })
                })
            {
                do {
                    try await storage.saveActiveTimerSessionAsync(nil)
                    result.activeTimerSession = nil
                } catch {
                    result.failures[.activeTimer] = error.localizedDescription
                }
            }

            if result.failures.isEmpty {
                result.consumableKeys.insert(.payloadNormalization)
                do {
                    _ = try await storage.normalizeAllPayloadsIfNeededAsync(
                        marker: "payloadNormalization.v1"
                    )
                } catch {
                    result.failures[.payloadNormalization] = error.localizedDescription
                }
                result.consumableKeys.insert(.automaticDistribution)
                do {
                    result.pendingAutomaticDistributionChanges =
                        try await storage.pendingAutomaticDistributionChangesAsync()
                } catch {
                    result.failures[.automaticDistribution] = error.localizedDescription
                }
            }
            return result
        }.value
        return storage.preloaded(with: preload)
    }
}
