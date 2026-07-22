import Foundation
import Compression

struct WeekflowPersistenceSnapshot {
    var goals: [WeeklyGoal] = []
    var channels: [TaskChannel] = []
    var calendarEvents: [CalendarEvent] = []
    var dailyPlanningStates: [DailyPlanningState] = []
    var focusRecords: [FocusRecord] = []
    var dailySummaries: [DailySummary] = []

    var isEmpty: Bool {
        goals.isEmpty
            && channels.isEmpty
            && calendarEvents.isEmpty
            && dailyPlanningStates.isEmpty
            && focusRecords.isEmpty
            && dailySummaries.isEmpty
    }
}

enum PersistenceMutationKind: Equatable {
    case userEdit
    case migration
    case automaticDistribution(transactionID: UUID)
    case undoAutomaticDistribution(transactionID: UUID)

    var title: String {
        switch self {
        case .userEdit: "userEdit"
        case .migration: "legacyMigration"
        case .automaticDistribution: "automaticDistribution"
        case .undoAutomaticDistribution: "undoAutomaticDistribution"
        }
    }

    var transactionID: UUID? {
        switch self {
        case let .automaticDistribution(transactionID): transactionID
        case .userEdit, .migration, .undoAutomaticDistribution: nil
        }
    }
}

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
}

protocol WeekflowPersistenceRepository: AnyObject {
    func loadGoals() throws -> [WeeklyGoal]?
    func loadChannels() throws -> [TaskChannel]?
    func loadCalendarEvents() throws -> [CalendarEvent]?
    func loadDailyPlanningStates() throws -> [DailyPlanningState]?
    func loadFocusRecords() throws -> [FocusRecord]?
    func loadDailySummaries() throws -> [DailySummary]?

    func saveGoals(_ goals: [WeeklyGoal], kind: PersistenceMutationKind) throws
    func saveChannels(_ channels: [TaskChannel], kind: PersistenceMutationKind) throws
    func saveCalendarEvents(_ events: [CalendarEvent], kind: PersistenceMutationKind) throws
    func saveDailyPlanningStates(_ states: [DailyPlanningState], kind: PersistenceMutationKind) throws
    func saveFocusRecords(_ records: [FocusRecord], kind: PersistenceMutationKind) throws
    func saveDailySummaries(_ summaries: [DailySummary], kind: PersistenceMutationKind) throws
    func importLegacySnapshot(_ snapshot: WeekflowPersistenceSnapshot) throws

    func pendingAutomaticDistributionChanges() throws -> [PersistedAutomaticDistributionChange]
    func commitAutomaticDistribution(transactionID: UUID) throws
    func detachAutomaticDistribution(taskID: UUID, transactionID: UUID) throws
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

private enum CompactDataCodec {
    private static let rawMarker: UInt8 = 0
    private static let compressedMarker: UInt8 = 1

    static func encode(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data([rawMarker]) }
        let capacity = max(data.count + data.count / 8 + 64, 256)
        var destination = Data(count: capacity)
        let compressedSize = data.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                compression_encode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    capacity,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard compressedSize > 0, compressedSize + 9 < data.count else {
            return Data([rawMarker]) + data
        }
        destination.count = compressedSize
        var originalSize = UInt64(data.count).littleEndian
        var result = Data([compressedMarker])
        withUnsafeBytes(of: &originalSize) { result.append(contentsOf: $0) }
        result.append(destination)
        return result
    }

    static func decode(_ data: Data) throws -> Data {
        guard let marker = data.first else { throw CompactDataCodecError.invalidHeader }
        if marker == rawMarker { return Data(data.dropFirst()) }
        guard marker == compressedMarker, data.count >= 9 else {
            throw CompactDataCodecError.invalidHeader
        }
        let originalSize = data.dropFirst().prefix(8).withUnsafeBytes {
            Int(UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)))
        }
        guard originalSize >= 0 else { throw CompactDataCodecError.invalidHeader }
        let compressed = data.dropFirst(9)
        var destination = Data(count: originalSize)
        let decodedSize = compressed.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                compression_decode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    originalSize,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    compressed.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard decodedSize == originalSize else { throw CompactDataCodecError.decodingFailed }
        return destination
    }
}

private enum CompactDataCodecError: Error {
    case invalidHeader
    case decodingFailed
}
