import Foundation
import SwiftData

// Generic payload CRUD, single-record upserts, and assignment normalization.

extension SwiftDataPersistenceRepository {
    func loadPayloads<Value: Decodable>(entityType: String, as type: Value.Type) throws -> [Value]? {
        let records = try context.fetch(FetchDescriptor<PersistedPayloadRecord>(
            predicate: #Predicate { $0.entityType == entityType }
        ))
        guard !records.isEmpty else { return nil }
        return try records.map { try CompactPersistenceCoding.decode(type, from: $0.payload) }
    }

    func savePayloads<Value: Encodable>(
        _ values: [Value],
        entityType: String,
        id: (Value) -> String,
        date: (Value) -> Date?,
        kind: PersistenceMutationKind
    ) throws {
        try PersistenceIdentityValidator.validatePayloadIDs(
            values,
            entityType: entityType,
            id: id
        )
        let existing = try context.fetch(FetchDescriptor<PersistedPayloadRecord>(
            predicate: #Predicate { $0.entityType == entityType }
        ))
        let lookup = Dictionary(keepingFirst: existing.map { ($0.entityID, $0) })
        let transaction = makeTransaction(kind: kind)
        var sequence = 0
        var desiredIDs = Set<String>()
        for value in values {
            let entityID = id(value)
            desiredIDs.insert(entityID)
            let payload = try CompactPersistenceCoding.encode(value)
            if let record = lookup[entityID] {
                guard record.payload != payload else { continue }
                recordOperation(
                    transactionID: transaction.id,
                    sequence: &sequence,
                    entityType: entityType,
                    entityID: entityID,
                    before: record.payload,
                    after: payload
                )
                record.payload = payload
                record.dateKey = date(value)
                record.revision += 1
                record.updatedAt = .now
            } else {
                context.insert(PersistedPayloadRecord(
                    key: "\(entityType):\(entityID)",
                    entityType: entityType,
                    entityID: entityID,
                    dateKey: date(value),
                    payload: payload
                ))
                recordOperation(
                    transactionID: transaction.id,
                    sequence: &sequence,
                    entityType: entityType,
                    entityID: entityID,
                    before: nil,
                    after: payload
                )
            }
        }
        for record in existing where !desiredIDs.contains(record.entityID) {
            recordOperation(
                transactionID: transaction.id,
                sequence: &sequence,
                entityType: entityType,
                entityID: record.entityID,
                before: record.payload,
                after: nil
            )
            context.delete(record)
        }
        try finish(transaction: transaction, operationCount: sequence, kind: kind)
    }

    // MARK: - Single-record payload upsert / delete (Phase 3-1)
    //
    // Finer-grained than `savePayloads`: fetches only the one record matching
    // `key` instead of scanning the whole entity type, so a single update is O(1)
    // in the number of stored records. Intended for large-data paths and single
    // edits (import/migration/one-record writes).
    //
    // NOTE on coalescing safety: the Store's batch-save paths deliberately keep
    // using `savePayloads`. Because the coordinator coalesces writes per domain,
    // a whole-array save is what guarantees no intermediate edit is lost when two
    // writes merge. Single-record upserts are safe where at most one record
    // changes per enqueued write (or where writes are not coalesced).

    func upsertPayload<Value: Encodable>(
        _ value: Value,
        entityType: String,
        entityID: String,
        date: Date?,
        kind: PersistenceMutationKind
    ) throws {
        let key = "\(entityType):\(entityID)"
        let payload = try CompactPersistenceCoding.encode(value)
        let existing = try context.fetch(FetchDescriptor<PersistedPayloadRecord>(
            predicate: #Predicate { $0.key == key }
        ))
        let transaction = makeTransaction(kind: kind)
        var sequence = 0
        if let record = existing.first {
            guard record.payload != payload else { return }   // unchanged: skip empty txn
            recordOperation(
                transactionID: transaction.id, sequence: &sequence,
                entityType: entityType, entityID: entityID,
                before: record.payload, after: payload
            )
            record.payload = payload
            record.dateKey = date
            record.revision += 1
            record.updatedAt = .now
        } else {
            context.insert(PersistedPayloadRecord(
                key: key, entityType: entityType, entityID: entityID,
                dateKey: date, payload: payload
            ))
            recordOperation(
                transactionID: transaction.id, sequence: &sequence,
                entityType: entityType, entityID: entityID, before: nil, after: payload
            )
        }
        try finish(transaction: transaction, operationCount: sequence, kind: kind)
    }

    func deletePayload(
        entityType: String,
        entityID: String,
        kind: PersistenceMutationKind
    ) throws {
        let key = "\(entityType):\(entityID)"
        let existing = try context.fetch(FetchDescriptor<PersistedPayloadRecord>(
            predicate: #Predicate { $0.key == key }
        ))
        guard let record = existing.first else { return }
        let transaction = makeTransaction(kind: kind)
        var sequence = 0
        recordOperation(
            transactionID: transaction.id, sequence: &sequence,
            entityType: entityType, entityID: entityID, before: record.payload, after: nil
        )
        context.delete(record)
        try finish(transaction: transaction, operationCount: sequence, kind: kind)
    }

    // Typed single-record convenience wrappers.
    func upsertCalendarEvent(_ event: CalendarEvent, kind: PersistenceMutationKind = .userEdit) throws {
        try upsertPayload(event, entityType: PersistenceEntity.calendarEvent, entityID: event.id.uuidString, date: event.startDate, kind: kind)
    }

    func deleteCalendarEvent(id: String, kind: PersistenceMutationKind = .userEdit) throws {
        try deletePayload(entityType: PersistenceEntity.calendarEvent, entityID: id, kind: kind)
    }

    func upsertFocusRecord(_ record: FocusRecord, kind: PersistenceMutationKind = .userEdit) throws {
        try upsertPayload(record, entityType: PersistenceEntity.focusSession, entityID: record.id.uuidString, date: businessCalendar.date(for: record.day), kind: kind)
    }

    func upsertDailySummary(_ summary: DailySummary, kind: PersistenceMutationKind = .userEdit) throws {
        try upsertPayload(summary, entityType: PersistenceEntity.dailyReview, entityID: summary.day.persistenceKey, date: businessCalendar.date(for: summary.day), kind: kind)
    }

    func upsertDailyPlanningState(
        _ state: DailyPlanningState,
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        try upsertPayload(
            state,
            entityType: PersistenceEntity.dailyPlan,
            entityID: state.day.persistenceKey,
            date: businessCalendar.date(for: state.day),
            kind: kind
        )
    }

    func upsertDailyPlanAndCalendarEvent(
        state: DailyPlanningState,
        event: CalendarEvent,
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        try performTransaction {
            try upsertDailyPlanningState(state, kind: kind)
            try faultInjector?(.afterDailyPlanWrite)
            try upsertCalendarEvent(event, kind: kind)
            try faultInjector?(.afterCalendarEventWrite)
            try faultInjector?(.beforeFinalSave)
        }
    }

    // MARK: - Assignment normalization

    func normalizedAssignments(
        for task: WeekTask,
        kind _: PersistenceMutationKind
    ) -> [DesiredAssignment] {
        var masks: [LocalDay: Int] = [:]
        if let plannedDay = task.plannedDay {
            masks[plannedDay, default: 0] |= 1
        }
        for day in task.assignedDays {
            masks[day, default: 0] |= 2
        }
        return masks.map { day, mask in
            return DesiredAssignment(
                key: assignmentKey(taskID: task.id, day: day),
                taskID: task.id,
                day: day,
                placementMask: mask,
                source: "manual",
                originTransactionID: nil
            )
        }
    }

    func assignmentSnapshot(_ record: PersistedTaskAssignmentRecord) -> AssignmentSnapshot {
        AssignmentSnapshot(
            taskID: record.taskID,
            day: assignmentDay(record) ?? businessCalendar.day(containing: record.day),
            placementMask: record.placementMask,
            source: record.source,
            originTransactionID: record.originTransactionID
        )
    }

    func assignmentDay(_ record: PersistedTaskAssignmentRecord) -> LocalDay? {
        guard let separator = record.uniquenessKey.lastIndex(of: ":") else {
            return businessCalendar.day(containing: record.day)
        }
        let key = String(record.uniquenessKey[record.uniquenessKey.index(after: separator)...])
        return (try? LocalDay(persistenceKey: key)) ?? businessCalendar.day(containing: record.day)
    }
}

// MARK: - Supporting types

struct AssignmentSnapshot: Codable, Equatable {
    let taskID: UUID
    let day: LocalDay
    let placementMask: Int
    let source: String
    let originTransactionID: UUID?
}

struct DesiredAssignment {
    let key: String
    let taskID: UUID
    let day: LocalDay
    let placementMask: Int
    let source: String
    let originTransactionID: UUID?

    var snapshot: AssignmentSnapshot {
        AssignmentSnapshot(
            taskID: taskID,
            day: day,
            placementMask: placementMask,
            source: source,
            originTransactionID: originTransactionID
        )
    }
}
