import Foundation
import Compression

struct WeekflowPersistenceSnapshot: Equatable {
    var goals: [WeeklyGoal] = []
    var plans: [WeeklyPlan] = []
    var channels: [TaskChannel] = []
    var calendarEvents: [CalendarEvent] = []
    var dailyPlanningStates: [DailyPlanningState] = []
    var focusRecords: [FocusRecord] = []
    var dailySummaries: [DailySummary] = []
    var activeTimerSession: TaskTimerSession? = nil

    var isEmpty: Bool {
        goals.isEmpty
            && plans.isEmpty
            && channels.isEmpty
            && calendarEvents.isEmpty
            && dailyPlanningStates.isEmpty
            && focusRecords.isEmpty
            && dailySummaries.isEmpty
            && activeTimerSession == nil
    }

    /// Canonical form used for migration verification. Only documented legacy
    /// normalization is permitted: assignment de-duplication, deterministic
    /// ordering and last-write-wins for one-record-per-day payloads.
    var canonicalized: WeekflowPersistenceSnapshot {
        var normalizedGoals = goals
        for goalIndex in normalizedGoals.indices {
            for taskIndex in normalizedGoals[goalIndex].tasks.indices {
                normalizedGoals[goalIndex].tasks[taskIndex].assignedDays = Array(Set(
                    normalizedGoals[goalIndex].tasks[taskIndex].assignedDays
                )).sorted()
            }
            normalizedGoals[goalIndex].tasks.sort {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
        normalizedGoals.sort {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
        let normalizedPlanningStates = Dictionary(grouping: dailyPlanningStates, by: \.day)
            .compactMap(\.value.last).sorted { $0.day < $1.day }
        let reviews = Dictionary(grouping: dailySummaries, by: \.day)
            .compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
            .sorted { $0.day < $1.day }
        return WeekflowPersistenceSnapshot(
            goals: normalizedGoals,
            plans: plans.sorted { $0.sortOrder < $1.sortOrder },
            channels: channels.sorted { $0.id < $1.id },
            calendarEvents: calendarEvents.sorted { $0.id.uuidString < $1.id.uuidString },
            dailyPlanningStates: normalizedPlanningStates,
            focusRecords: focusRecords.sorted { $0.id.uuidString < $1.id.uuidString },
            dailySummaries: reviews,
            activeTimerSession: activeTimerSession
        )
    }
}

enum PersistenceMutationKind: Equatable {
    case userEdit
    case migration
    case automaticDistribution(transactionID: UUID)
    case undoAutomaticDistribution(transactionID: UUID)
    case manualOverride(taskID: UUID, transactionID: UUID)

    var title: String {
        switch self {
        case .userEdit: "userEdit"
        case .migration: "legacyMigration"
        case .automaticDistribution: "automaticDistribution"
        case .undoAutomaticDistribution: "undoAutomaticDistribution"
        case .manualOverride: "manualOverride"
        }
    }

    var transactionID: UUID? {
        switch self {
        case let .automaticDistribution(transactionID): transactionID
        case .userEdit, .migration, .undoAutomaticDistribution, .manualOverride: nil
        }
    }
}

enum PersistenceFaultPoint: String, CaseIterable, Sendable {
    case beforeFirstWrite
    case afterGoalWrite
    case afterTaskWrite
    case afterAssignmentWrite
    case afterDailyPlanWrite
    case afterCalendarEventWrite
    case beforeFinalSave
    case duringNormalization
}

typealias PersistenceFaultInjector = @Sendable (PersistenceFaultPoint) throws -> Void

struct PersistedAutomaticDistributionChange: Equatable {
    let transactionID: UUID
    let goalID: UUID
    let taskID: UUID
    let assignedDate: Date
}

struct PersistenceDiagnostics: Equatable {
    let goalCount: Int
    let taskCount: Int
    let assignmentCount: Int
    let transactionCount: Int
    let operationCount: Int
    let payloadByteCount: Int
    let historyByteCount: Int
    let oldestTransactionDate: Date?
    let cleanableTransactionCount: Int
}

struct MutationHistoryCandidate: Equatable {
    let id: UUID
    let kind: String
    let createdAt: Date
    let isUndoable: Bool
}

enum MutationHistoryRetentionPolicy {
    static func removableIDs(
        from candidates: [MutationHistoryCandidate],
        now: Date,
        maximumCount: Int,
        retentionDays: Int
    ) -> Set<UUID> {
        let cutoff = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -retentionDays,
            to: now
        ) ?? .distantPast
        let ordinary = candidates
            .filter { $0.kind == PersistenceMutationKind.userEdit.title && !$0.isUndoable }
            .sorted { $0.createdAt > $1.createdAt }
        let retained = Set(ordinary.prefix(maximumCount).map(\.id))
        return Set(ordinary.lazy.filter {
            $0.createdAt < cutoff || !retained.contains($0.id)
        }.map(\.id))
    }
}

struct PersistedTaskUpsert: Equatable {
    let goalID: UUID
    let task: WeekTask
}

struct PersistenceGoalChangeSet: Equatable {
    var goalsToUpsert: [WeeklyGoal] = []
    var goalIDsToDelete: [UUID] = []
    var tasksToUpsert: [PersistedTaskUpsert] = []
    var taskIDsToDelete: [UUID] = []

    var isEmpty: Bool {
        goalsToUpsert.isEmpty && goalIDsToDelete.isEmpty
            && tasksToUpsert.isEmpty && taskIDsToDelete.isEmpty
    }

    static func difference(before: [WeeklyGoal], after: [WeeklyGoal]) -> Self {
        let oldGoals = Dictionary(keepingFirst: before.map { ($0.id, $0) })
        let newGoals = Dictionary(keepingFirst: after.map { ($0.id, $0) })
        var result = Self()
        result.goalIDsToDelete = oldGoals.keys.filter { newGoals[$0] == nil }
        for goal in after {
            var envelope = goal
            envelope.tasks = []
            var oldEnvelope = oldGoals[goal.id]
            oldEnvelope?.tasks = []
            if oldEnvelope != envelope { result.goalsToUpsert.append(goal) }
        }

        let oldTasks = Dictionary(keepingFirst: before.flatMap { goal in
            goal.tasks.map { ($0.id, PersistedTaskUpsert(goalID: goal.id, task: $0)) }
        })
        let newTasks = Dictionary(keepingFirst: after.flatMap { goal in
            goal.tasks.map { ($0.id, PersistedTaskUpsert(goalID: goal.id, task: $0)) }
        })
        result.taskIDsToDelete = oldTasks.keys.filter { newTasks[$0] == nil }
        result.tasksToUpsert = newTasks.values.filter { oldTasks[$0.task.id] != $0 }
        return result
    }
}

protocol WeekflowPersistenceRepository: AnyObject {
    func loadGoals() throws -> [WeeklyGoal]?
    func loadPlans() throws -> [WeeklyPlan]?
    func loadChannels() throws -> [TaskChannel]?
    func loadCalendarEvents() throws -> [CalendarEvent]?
    func loadDailyPlanningStates() throws -> [DailyPlanningState]?
    func loadFocusRecords() throws -> [FocusRecord]?
    func loadDailySummaries() throws -> [DailySummary]?
    func loadActiveTimerSession() throws -> TaskTimerSession?

    func saveGoals(_ goals: [WeeklyGoal], kind: PersistenceMutationKind) throws
    func savePlans(_ plans: [WeeklyPlan], kind: PersistenceMutationKind) throws
    func applyGoalChanges(_ changes: PersistenceGoalChangeSet, kind: PersistenceMutationKind) throws
    func saveChannels(_ channels: [TaskChannel], kind: PersistenceMutationKind) throws
    func saveCalendarEvents(_ events: [CalendarEvent], kind: PersistenceMutationKind) throws
    func saveDailyPlanningStates(_ states: [DailyPlanningState], kind: PersistenceMutationKind) throws
    func saveFocusRecords(_ records: [FocusRecord], kind: PersistenceMutationKind) throws
    func saveDailySummaries(_ summaries: [DailySummary], kind: PersistenceMutationKind) throws
    func saveActiveTimerSession(_ session: TaskTimerSession?) throws
    // Phase 3-1: single-record upsert / delete (O(1) in stored record count).
    func upsertCalendarEvent(_ event: CalendarEvent, kind: PersistenceMutationKind) throws
    func deleteCalendarEvent(id: String, kind: PersistenceMutationKind) throws
    func upsertFocusRecord(_ record: FocusRecord, kind: PersistenceMutationKind) throws
    func upsertDailySummary(_ summary: DailySummary, kind: PersistenceMutationKind) throws
    func upsertDailyPlanningState(_ state: DailyPlanningState, kind: PersistenceMutationKind) throws
    func upsertDailyPlanAndCalendarEvent(
        state: DailyPlanningState,
        event: CalendarEvent,
        kind: PersistenceMutationKind
    ) throws
    func importLegacySnapshot(_ snapshot: WeekflowPersistenceSnapshot) throws
    func saveApplicationSnapshot(
        _ snapshot: WeekflowPersistenceSnapshot,
        kind: PersistenceMutationKind
    ) throws
    func saveDailyPlanAndCalendarEvents(
        states: [DailyPlanningState],
        events: [CalendarEvent],
        kind: PersistenceMutationKind
    ) throws
    func saveGoalChangesAndActiveTimer(
        changes: PersistenceGoalChangeSet,
        session: TaskTimerSession?,
        kind: PersistenceMutationKind
    ) throws

    func pendingAutomaticDistributionChanges() throws -> [PersistedAutomaticDistributionChange]
    func commitAutomaticDistribution(transactionID: UUID) throws
    func detachAutomaticDistribution(taskID: UUID, transactionID: UUID) throws
    /// P1-1: Eagerly re-encode all payloads to the current format.
    @discardableResult func normalizeAllPayloads() throws -> Int
    @discardableResult func normalizeAllPayloadsIfNeeded(marker: String) throws -> Int
    func diagnostics() throws -> PersistenceDiagnostics
}

enum CompactPersistenceCoding {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return CompactDataCodec.encode(try encoder.encode(value))
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try PropertyListDecoder().decode(type, from: CompactDataCodec.decode(data))
    }
}

enum CompactDataCodec {
    static let maximumDecodedSize = 64 * 1024 * 1024

    private static let magic: UInt8 = 0x57
    private static let formatVersion: UInt8 = 2
    private static let rawMarker: UInt8 = 0
    private static let compressedMarker: UInt8 = 1
    private static let version1HeaderSize = 15
    private static let version2HeaderSize = 19

    static func encode(_ data: Data) -> Data {
        let capacity = max(data.count + data.count / 8 + 64, 256)
        var destination = Data(count: capacity)
        let compressedSize = data.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                guard let destinationAddress = destinationBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let sourceAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(
                    destinationAddress,
                    capacity,
                    sourceAddress,
                    data.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard compressedSize > 0, compressedSize + version2HeaderSize < data.count else {
            return versionedPayload(marker: rawMarker, original: data, body: data)
        }
        destination.count = compressedSize
        return versionedPayload(marker: compressedMarker, original: data, body: destination)
    }

    static func decode(_ data: Data) throws -> Data {
        guard let marker = data.first else { throw CompactDataCodecError.invalidHeader }
        if marker == magic {
            return try decodeVersioned(data)
        }
        // V0 compatibility is read-only. All new writes use the checksummed V1
        // envelope, allowing existing databases to upgrade without rewriting.
        if marker == rawMarker {
            let payload = Data(data.dropFirst())
            guard !payload.isEmpty else { throw CompactDataCodecError.truncatedPayload }
            guard payload.count <= maximumDecodedSize else {
                throw CompactDataCodecError.decodedSizeExceedsLimit(payload.count)
            }
            return payload
        }
        guard marker == compressedMarker else { throw CompactDataCodecError.unknownMarker(marker) }
        guard data.count >= 9 else { throw CompactDataCodecError.invalidHeader }
        let originalSize = try decodedSize(from: data.dropFirst().prefix(8))
        let compressed = data.dropFirst(9)
        guard !compressed.isEmpty else { throw CompactDataCodecError.emptyCompressedPayload }
        return try decompress(compressed, originalSize: originalSize)
    }

    private static func versionedPayload(marker: UInt8, original: Data, body: Data) -> Data {
        var size = UInt64(original.count).littleEndian
        var contentChecksum = checksum(of: original).littleEndian
        var bodyChecksum = checksum(of: body).littleEndian
        var result = Data([magic, formatVersion, marker])
        withUnsafeBytes(of: &size) { result.append(contentsOf: $0) }
        withUnsafeBytes(of: &contentChecksum) { result.append(contentsOf: $0) }
        withUnsafeBytes(of: &bodyChecksum) { result.append(contentsOf: $0) }
        result.append(body)
        return result
    }

    private static func decodeVersioned(_ data: Data) throws -> Data {
        guard data.count >= version1HeaderSize else { throw CompactDataCodecError.invalidHeader }
        let version = data[data.startIndex + 1]
        guard version == 1 || version == formatVersion else {
            throw CompactDataCodecError.unsupportedVersion(version)
        }
        let headerSize = version == 1 ? version1HeaderSize : version2HeaderSize
        guard data.count >= headerSize else { throw CompactDataCodecError.invalidHeader }
        let marker = data[data.startIndex + 2]
        guard marker == rawMarker || marker == compressedMarker else {
            throw CompactDataCodecError.unknownMarker(marker)
        }
        let sizeStart = data.startIndex + 3
        let originalSize = try decodedSize(from: data[sizeStart..<(sizeStart + 8)])
        let checksumStart = sizeStart + 8
        let expectedChecksum = data[checksumStart..<(checksumStart + 4)].withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
        }
        let body: Data.SubSequence
        if version == 2 {
            let bodyChecksumStart = checksumStart + 4
            let expectedBodyChecksum = data[bodyChecksumStart..<(bodyChecksumStart + 4)].withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
            }
            body = data.dropFirst(version2HeaderSize)
            guard checksum(of: Data(body)) == expectedBodyChecksum else {
                throw CompactDataCodecError.checksumMismatch
            }
        } else {
            body = data.dropFirst(version1HeaderSize)
        }
        let decoded: Data
        if marker == rawMarker {
            guard body.count == originalSize else {
                throw CompactDataCodecError.lengthMismatch(expected: originalSize, actual: body.count)
            }
            decoded = Data(body)
        } else {
            guard !body.isEmpty else { throw CompactDataCodecError.emptyCompressedPayload }
            decoded = try decompress(body, originalSize: originalSize)
        }
        guard checksum(of: decoded) == expectedChecksum else {
            throw CompactDataCodecError.checksumMismatch
        }
        return decoded
    }

    private static func decodedSize<C: Collection>(from bytes: C) throws -> Int where C.Element == UInt8 {
        guard bytes.count == 8 else { throw CompactDataCodecError.invalidHeader }
        let encoded = Data(bytes).withUnsafeBytes {
            UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self))
        }
        guard let size = Int(exactly: encoded) else {
            throw CompactDataCodecError.invalidDecodedSize(encoded)
        }
        guard size <= maximumDecodedSize else {
            throw CompactDataCodecError.decodedSizeExceedsLimit(size)
        }
        return size
    }

    private static func decompress<C: Collection>(_ compressed: C, originalSize: Int) throws -> Data where C.Element == UInt8 {
        guard originalSize > 0 else {
            throw CompactDataCodecError.lengthMismatch(expected: originalSize, actual: 0)
        }
        let compressedData = Data(compressed)
        var destination = Data(count: originalSize)
        let decodedSize = compressedData.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                guard let destinationAddress = destinationBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let sourceAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationAddress,
                    originalSize,
                    sourceAddress,
                    compressedData.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard decodedSize == originalSize else {
            throw CompactDataCodecError.lengthMismatch(expected: originalSize, actual: decodedSize)
        }
        return destination
    }

    private static func checksum(of data: Data) -> UInt32 {
        data.reduce(UInt32(2_166_136_261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16_777_619
        }
    }
}

enum CompactDataCodecError: LocalizedError, Equatable {
    case invalidHeader
    case truncatedPayload
    case unknownMarker(UInt8)
    case unsupportedVersion(UInt8)
    case invalidDecodedSize(UInt64)
    case decodedSizeExceedsLimit(Int)
    case emptyCompressedPayload
    case lengthMismatch(expected: Int, actual: Int)
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidHeader: "压缩数据头不完整。"
        case .truncatedPayload: "压缩数据内容缺失。"
        case let .unknownMarker(marker): "未知的压缩数据标记：\(marker)。"
        case let .unsupportedVersion(version): "不支持的压缩数据版本：\(version)。"
        case let .invalidDecodedSize(size): "压缩数据声明了无法转换的长度：\(size)。"
        case let .decodedSizeExceedsLimit(size): "解压长度 \(size) 超过 64 MB 安全上限。"
        case .emptyCompressedPayload: "压缩内容为空。"
        case let .lengthMismatch(expected, actual): "解压长度不一致（期望 \(expected)，实际 \(actual)）。"
        case .checksumMismatch: "压缩数据校验失败。"
        }
    }
}
