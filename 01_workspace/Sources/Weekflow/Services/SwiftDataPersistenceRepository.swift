import Foundation
import SwiftData

final class SwiftDataPersistenceRepository: WeekflowPersistenceRepository {
    static let schemaVersion = 1

    let storeURL: URL
    private let container: ModelContainer
    private let context: ModelContext
    private let calendar: Calendar

    init(storeURL: URL, calendar: Calendar = .current) throws {
        self.storeURL = storeURL
        self.calendar = calendar
        let schema = Schema([
            PersistenceMetadataRecord.self,
            PersistedGoalRecord.self,
            PersistedTaskRecord.self,
            PersistedTaskAssignmentRecord.self,
            PersistedPayloadRecord.self,
            PersistedLifecycleEventRecord.self,
            PersistedMutationTransactionRecord.self,
            PersistedMutationOperationRecord.self
        ])
        let configuration = ModelConfiguration(
            "Weekflow",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
        try pruneRedundantMigrationHistoryIfNeeded()
    }

    func loadGoals() throws -> [WeeklyGoal]? {
        let goalRecords = try context.fetch(FetchDescriptor<PersistedGoalRecord>())
        guard !goalRecords.isEmpty else { return nil }
        let taskRecords = try context.fetch(FetchDescriptor<PersistedTaskRecord>())
        let assignmentRecords = try context.fetch(FetchDescriptor<PersistedTaskAssignmentRecord>())
        let assignmentsByTask = Dictionary(grouping: assignmentRecords, by: \.taskID)
        let tasksByGoal = try Dictionary(grouping: taskRecords) { $0.goalID }
            .mapValues { records in
                try records.map { record in
                    var task = try CompactPersistenceCoding.decode(WeekTask.self, from: record.payload)
                    let assignments = assignmentsByTask[record.id] ?? []
                    task.plannedDate = assignments.first(where: { $0.placementMask & 1 != 0 })?.day
                    task.assignedDates = assignments
                        .filter { $0.placementMask & 2 != 0 }
                        .map(\.day)
                        .sorted()
                    return task
                }
            }
        return try goalRecords.map { record in
            var goal = try CompactPersistenceCoding.decode(WeeklyGoal.self, from: record.payload)
            goal.tasks = (tasksByGoal[record.id] ?? []).sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
            return goal
        }
        .sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.startDate < $1.startDate
        }
    }

    func loadChannels() throws -> [TaskChannel]? {
        try loadPayloads(entityType: "channel", as: TaskChannel.self)
    }

    func loadCalendarEvents() throws -> [CalendarEvent]? {
        try loadPayloads(entityType: "calendarEvent", as: CalendarEvent.self)
    }

    func loadDailyPlanningStates() throws -> [DailyPlanningState]? {
        let values = try loadPayloads(entityType: "dailyPlan", as: DailyPlanningState.self)
        return values?.sorted { $0.date < $1.date }
    }

    func loadFocusRecords() throws -> [FocusRecord]? {
        let values = try loadPayloads(entityType: "focusSession", as: FocusRecord.self)
        return values?.sorted { $0.date < $1.date }
    }

    func loadDailySummaries() throws -> [DailySummary]? {
        let values = try loadPayloads(entityType: "dailyReview", as: DailySummary.self)
        return values?.sorted { $0.date < $1.date }
    }

    func saveGoals(_ goals: [WeeklyGoal], kind: PersistenceMutationKind = .userEdit) throws {
        let existingGoals = try context.fetch(FetchDescriptor<PersistedGoalRecord>())
        let existingTasks = try context.fetch(FetchDescriptor<PersistedTaskRecord>())
        let existingAssignments = try context.fetch(FetchDescriptor<PersistedTaskAssignmentRecord>())
        let goalLookup = Dictionary(uniqueKeysWithValues: existingGoals.map { ($0.id, $0) })
        let taskLookup = Dictionary(uniqueKeysWithValues: existingTasks.map { ($0.id, $0) })
        let assignmentLookup = Dictionary(uniqueKeysWithValues: existingAssignments.map { ($0.uniquenessKey, $0) })

        var desiredGoalIDs = Set<UUID>()
        var desiredTaskIDs = Set<UUID>()
        var desiredAssignmentKeys = Set<String>()
        let transaction = makeTransaction(kind: kind)
        var sequence = 0

        for goal in goals {
            desiredGoalIDs.insert(goal.id)
            var goalEnvelope = goal
            goalEnvelope.tasks = []
            let payload = try CompactPersistenceCoding.encode(goalEnvelope)
            let lifecycle = lifecycleState(for: goal).rawValue
            if let record = goalLookup[goal.id] {
                if record.payload != payload || record.lifecycleState != lifecycle {
                    recordOperation(
                        transactionID: transaction.id,
                        sequence: &sequence,
                        entityType: "goal",
                        entityID: goal.id.uuidString,
                        before: record.payload,
                        after: payload
                    )
                    recordLifecycleChange(
                        entityType: "goal",
                        entityID: goal.id.uuidString,
                        from: record.lifecycleState,
                        to: lifecycle,
                        transactionID: transaction.id
                    )
                    record.payload = payload
                    record.periodStart = goal.startDate
                    record.periodEnd = goal.endDate
                    record.channelID = goal.channelID
                    record.lifecycleState = lifecycle
                    record.revision += 1
                    record.updatedAt = .now
                }
            } else {
                let record = PersistedGoalRecord(
                    id: goal.id,
                    payload: payload,
                    periodStart: goal.startDate,
                    periodEnd: goal.endDate,
                    channelID: goal.channelID,
                    lifecycleState: lifecycle,
                    revision: 1,
                    updatedAt: .now
                )
                context.insert(record)
                recordOperation(
                    transactionID: transaction.id,
                    sequence: &sequence,
                    entityType: "goal",
                    entityID: goal.id.uuidString,
                    before: nil,
                    after: payload
                )
                recordLifecycleChange(
                    entityType: "goal",
                    entityID: goal.id.uuidString,
                    from: PersistedLifecycleState.purged.rawValue,
                    to: lifecycle,
                    transactionID: transaction.id
                )
            }

            for task in goal.tasks {
                desiredTaskIDs.insert(task.id)
                var taskEnvelope = task
                taskEnvelope.plannedDate = nil
                taskEnvelope.assignedDates = []
                let taskPayload = try CompactPersistenceCoding.encode(taskEnvelope)
                let taskLifecycle = lifecycleState(for: task).rawValue
                if let record = taskLookup[task.id] {
                    if record.payload != taskPayload || record.lifecycleState != taskLifecycle {
                        recordOperation(
                            transactionID: transaction.id,
                            sequence: &sequence,
                            entityType: "task",
                            entityID: task.id.uuidString,
                            before: record.payload,
                            after: taskPayload
                        )
                        recordLifecycleChange(
                            entityType: "task",
                            entityID: task.id.uuidString,
                            from: record.lifecycleState,
                            to: taskLifecycle,
                            transactionID: transaction.id
                        )
                        record.goalID = goal.id
                        record.subgoalID = task.subgoalID
                        record.payload = taskPayload
                        record.channelID = task.channelID
                        record.lifecycleState = taskLifecycle
                        record.revision += 1
                        record.updatedAt = task.updatedAt
                    }
                } else {
                    context.insert(PersistedTaskRecord(
                        id: task.id,
                        goalID: goal.id,
                        subgoalID: task.subgoalID,
                        payload: taskPayload,
                        channelID: task.channelID,
                        lifecycleState: taskLifecycle,
                        revision: 1,
                        updatedAt: task.updatedAt
                    ))
                    recordOperation(
                        transactionID: transaction.id,
                        sequence: &sequence,
                        entityType: "task",
                        entityID: task.id.uuidString,
                        before: nil,
                        after: taskPayload
                    )
                }

                for assignment in normalizedAssignments(for: task, kind: kind) {
                    desiredAssignmentKeys.insert(assignment.key)
                    if let record = assignmentLookup[assignment.key] {
                        let before = try CompactPersistenceCoding.encode(assignmentSnapshot(record))
                        let updatedSnapshot = AssignmentSnapshot(
                            taskID: assignment.taskID,
                            day: assignment.day,
                            placementMask: assignment.placementMask,
                            source: record.source,
                            originTransactionID: record.originTransactionID
                        )
                        let after = try CompactPersistenceCoding.encode(updatedSnapshot)
                        if before != after {
                            recordOperation(
                                transactionID: transaction.id,
                                sequence: &sequence,
                                entityType: "taskAssignment",
                                entityID: record.id.uuidString,
                                before: before,
                                after: after
                            )
                            record.day = assignment.day
                            record.placementMask = assignment.placementMask
                            record.revision += 1
                        }
                    } else {
                        let automaticTransactionID: UUID?
                        if case let .automaticDistribution(transactionID) = kind,
                           assignment.placementMask & 2 != 0 {
                            automaticTransactionID = transactionID
                        } else {
                            automaticTransactionID = nil
                        }
                        let source = automaticTransactionID == nil ? "manual" : "automatic"
                        let record = PersistedTaskAssignmentRecord(
                            uniquenessKey: assignment.key,
                            taskID: task.id,
                            day: assignment.day,
                            placementMask: assignment.placementMask,
                            source: source,
                            originTransactionID: automaticTransactionID
                        )
                        context.insert(record)
                        recordOperation(
                            transactionID: transaction.id,
                            sequence: &sequence,
                            entityType: "taskAssignment",
                            entityID: record.id.uuidString,
                            before: nil,
                            after: try CompactPersistenceCoding.encode(AssignmentSnapshot(
                                taskID: assignment.taskID,
                                day: assignment.day,
                                placementMask: assignment.placementMask,
                                source: source,
                                originTransactionID: automaticTransactionID
                            ))
                        )
                    }
                }
            }
        }

        for record in existingAssignments where !desiredAssignmentKeys.contains(record.uniquenessKey) {
            recordOperation(
                transactionID: transaction.id,
                sequence: &sequence,
                entityType: "taskAssignment",
                entityID: record.id.uuidString,
                before: try CompactPersistenceCoding.encode(assignmentSnapshot(record)),
                after: nil
            )
            context.delete(record)
        }
        for record in existingTasks where !desiredTaskIDs.contains(record.id) {
            recordOperation(
                transactionID: transaction.id,
                sequence: &sequence,
                entityType: "task",
                entityID: record.id.uuidString,
                before: record.payload,
                after: nil
            )
            if record.lifecycleState == PersistedLifecycleState.trashed.rawValue {
                recordLifecycleChange(
                    entityType: "task",
                    entityID: record.id.uuidString,
                    from: record.lifecycleState,
                    to: PersistedLifecycleState.purged.rawValue,
                    transactionID: transaction.id
                )
            }
            context.delete(record)
        }
        for record in existingGoals where !desiredGoalIDs.contains(record.id) {
            recordOperation(
                transactionID: transaction.id,
                sequence: &sequence,
                entityType: "goal",
                entityID: record.id.uuidString,
                before: record.payload,
                after: nil
            )
            if record.lifecycleState == PersistedLifecycleState.trashed.rawValue {
                recordLifecycleChange(
                    entityType: "goal",
                    entityID: record.id.uuidString,
                    from: record.lifecycleState,
                    to: PersistedLifecycleState.purged.rawValue,
                    transactionID: transaction.id
                )
            }
            context.delete(record)
        }

        try finish(transaction: transaction, operationCount: sequence, kind: kind)
    }

    func saveChannels(_ channels: [TaskChannel], kind: PersistenceMutationKind = .userEdit) throws {
        try savePayloads(
            channels,
            entityType: "channel",
            id: { $0.id },
            date: { $0.archivedAt },
            kind: kind
        )
    }

    func saveCalendarEvents(_ events: [CalendarEvent], kind: PersistenceMutationKind = .userEdit) throws {
        try savePayloads(events, entityType: "calendarEvent", id: { $0.id.uuidString }, date: { $0.startDate }, kind: kind)
    }

    func saveDailyPlanningStates(_ states: [DailyPlanningState], kind: PersistenceMutationKind = .userEdit) throws {
        let unique = Dictionary(grouping: states) { dayKey($0.date) }.compactMap { $0.value.last }
        try savePayloads(unique, entityType: "dailyPlan", id: { dayKey($0.date) }, date: { $0.date }, kind: kind)
    }

    func saveFocusRecords(_ records: [FocusRecord], kind: PersistenceMutationKind = .userEdit) throws {
        try savePayloads(records, entityType: "focusSession", id: { $0.id.uuidString }, date: { $0.date }, kind: kind)
    }

    func saveDailySummaries(_ summaries: [DailySummary], kind: PersistenceMutationKind = .userEdit) throws {
        let unique = Dictionary(grouping: summaries) { dayKey($0.date) }.compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
        try savePayloads(unique, entityType: "dailyReview", id: { dayKey($0.date) }, date: { $0.date }, kind: kind)
    }

    func importLegacySnapshot(_ snapshot: WeekflowPersistenceSnapshot) throws {
        try saveGoals(snapshot.goals, kind: .migration)
        try saveChannels(snapshot.channels, kind: .migration)
        try saveCalendarEvents(snapshot.calendarEvents, kind: .migration)
        try saveDailyPlanningStates(snapshot.dailyPlanningStates, kind: .migration)
        try saveFocusRecords(snapshot.focusRecords, kind: .migration)
        try saveDailySummaries(snapshot.dailySummaries, kind: .migration)
        setMetadata(key: "schemaVersion", value: String(Self.schemaVersion))
        setMetadata(key: "migrationState", value: "complete")
        try context.save()
    }

    func pendingAutomaticDistributionChanges() throws -> [PersistedAutomaticDistributionChange] {
        let automaticKind = "automaticDistribution"
        let availableState = "available"
        let transactions = try context.fetch(FetchDescriptor<PersistedMutationTransactionRecord>(
            predicate: #Predicate {
                $0.kind == automaticKind && $0.committedAt == nil && $0.undoState == availableState
            }
        ))
        guard let transaction = transactions.max(by: { $0.createdAt < $1.createdAt }) else { return [] }
        let transactionID = transaction.id
        let assignments = try context.fetch(FetchDescriptor<PersistedTaskAssignmentRecord>(
            predicate: #Predicate { $0.originTransactionID == transactionID }
        ))
        let taskGoalLookup = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<PersistedTaskRecord>()).map { ($0.id, $0.goalID) }
        )
        return assignments.compactMap { assignment in
            guard let goalID = taskGoalLookup[assignment.taskID] else { return nil }
            return PersistedAutomaticDistributionChange(
                transactionID: transaction.id,
                goalID: goalID,
                taskID: assignment.taskID,
                assignedDate: assignment.day
            )
        }
    }

    func commitAutomaticDistribution(transactionID: UUID) throws {
        var descriptor = FetchDescriptor<PersistedMutationTransactionRecord>(
            predicate: #Predicate { $0.id == transactionID }
        )
        descriptor.fetchLimit = 1
        guard let transaction = try context.fetch(descriptor).first else { return }
        transaction.committedAt = .now
        transaction.undoState = "committed"
        try context.save()
    }

    func detachAutomaticDistribution(taskID: UUID, transactionID: UUID) throws {
        let matchingAssignments = try context.fetch(FetchDescriptor<PersistedTaskAssignmentRecord>(
            predicate: #Predicate {
                $0.taskID == taskID && $0.originTransactionID == transactionID
            }
        ))
        guard !matchingAssignments.isEmpty else { return }

        let mutation = makeTransaction(kind: .userEdit)
        var sequence = 0
        for assignment in matchingAssignments {
            let before = try CompactPersistenceCoding.encode(assignmentSnapshot(assignment))
            assignment.source = "manual"
            assignment.originTransactionID = nil
            assignment.revision += 1
            let after = try CompactPersistenceCoding.encode(assignmentSnapshot(assignment))
            recordOperation(
                transactionID: mutation.id,
                sequence: &sequence,
                entityType: "taskAssignment",
                entityID: assignment.id.uuidString,
                before: before,
                after: after
            )
        }

        let remaining = try context.fetch(FetchDescriptor<PersistedTaskAssignmentRecord>(
            predicate: #Predicate { $0.originTransactionID == transactionID }
        ))
        if remaining.isEmpty {
            var descriptor = FetchDescriptor<PersistedMutationTransactionRecord>(
                predicate: #Predicate { $0.id == transactionID }
            )
            descriptor.fetchLimit = 1
            if let original = try context.fetch(descriptor).first {
                original.committedAt = .now
                original.undoState = "committed"
            }
        }
        try finish(transaction: mutation, operationCount: sequence, kind: .userEdit)
    }

    func diagnostics() throws -> PersistenceDiagnostics {
        let goals = try context.fetch(FetchDescriptor<PersistedGoalRecord>())
        let tasks = try context.fetch(FetchDescriptor<PersistedTaskRecord>())
        let assignments = try context.fetch(FetchDescriptor<PersistedTaskAssignmentRecord>())
        let payloads = try context.fetch(FetchDescriptor<PersistedPayloadRecord>())
        let transactions = try context.fetch(FetchDescriptor<PersistedMutationTransactionRecord>())
        let operations = try context.fetch(FetchDescriptor<PersistedMutationOperationRecord>())
        let goalBytes = goals.reduce(0) { $0 + $1.payload.count }
        let taskBytes = tasks.reduce(0) { $0 + $1.payload.count }
        let otherPayloadBytes = payloads.reduce(0) { $0 + $1.payload.count }
        let operationBytes = operations.reduce(0) { partial, operation in
            partial + (operation.beforeValue?.count ?? 0) + (operation.afterValue?.count ?? 0)
        }
        return PersistenceDiagnostics(
            goalCount: goals.count,
            taskCount: tasks.count,
            assignmentCount: assignments.count,
            transactionCount: transactions.count,
            operationCount: operations.count,
            payloadByteCount: goalBytes + taskBytes + otherPayloadBytes + operationBytes
        )
    }

    private func loadPayloads<Value: Decodable>(entityType: String, as type: Value.Type) throws -> [Value]? {
        let records = try context.fetch(FetchDescriptor<PersistedPayloadRecord>(
            predicate: #Predicate { $0.entityType == entityType }
        ))
        guard !records.isEmpty else { return nil }
        return try records.map { try CompactPersistenceCoding.decode(type, from: $0.payload) }
    }

    private func savePayloads<Value: Encodable>(
        _ values: [Value],
        entityType: String,
        id: (Value) -> String,
        date: (Value) -> Date?,
        kind: PersistenceMutationKind
    ) throws {
        let existing = try context.fetch(FetchDescriptor<PersistedPayloadRecord>(
            predicate: #Predicate { $0.entityType == entityType }
        ))
        let lookup = Dictionary(uniqueKeysWithValues: existing.map { ($0.entityID, $0) })
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

    private func makeTransaction(kind: PersistenceMutationKind) -> PersistedMutationTransactionRecord {
        let transaction = PersistedMutationTransactionRecord(
            id: kind.transactionID ?? UUID(),
            kind: kind.title,
            compensatesTransactionID: {
                if case let .undoAutomaticDistribution(transactionID) = kind { return transactionID }
                return nil
            }()
        )
        context.insert(transaction)
        return transaction
    }

    private func finish(
        transaction: PersistedMutationTransactionRecord,
        operationCount: Int,
        kind: PersistenceMutationKind
    ) throws {
        if kind == .migration {
            // The untouched JSON plus its read-only backup are the migration
            // rollback source. Keeping a second copy of every imported value
            // in the mutation log would only inflate the new database.
            let transactionID = transaction.id
            let operations = try context.fetch(FetchDescriptor<PersistedMutationOperationRecord>(
                predicate: #Predicate { $0.transactionID == transactionID }
            ))
            for operation in operations { context.delete(operation) }
            let lifecycleEvents = try context.fetch(FetchDescriptor<PersistedLifecycleEventRecord>(
                predicate: #Predicate { $0.transactionID == transactionID }
            ))
            for event in lifecycleEvents { context.delete(event) }
            context.delete(transaction)
            try context.save()
            return
        }
        guard operationCount > 0 else {
            context.delete(transaction)
            return
        }
        if case let .undoAutomaticDistribution(originalID) = kind {
            let transactions = try context.fetch(FetchDescriptor<PersistedMutationTransactionRecord>())
            if let original = transactions.first(where: { $0.id == originalID }) {
                original.undoState = "undone"
            }
        }
        setMetadata(key: "schemaVersion", value: String(Self.schemaVersion))
        setMetadata(key: "migrationState", value: "native")
        try context.save()
    }

    private func recordOperation(
        transactionID: UUID,
        sequence: inout Int,
        entityType: String,
        entityID: String,
        before: Data?,
        after: Data?
    ) {
        context.insert(PersistedMutationOperationRecord(
            transactionID: transactionID,
            sequence: sequence,
            entityType: entityType,
            entityID: entityID,
            beforeValue: before,
            afterValue: after
        ))
        sequence += 1
    }

    private func recordLifecycleChange(
        entityType: String,
        entityID: String,
        from: String,
        to: String,
        transactionID: UUID
    ) {
        guard from != to else { return }
        context.insert(PersistedLifecycleEventRecord(
            entityType: entityType,
            entityID: entityID,
            fromState: from,
            toState: to,
            transactionID: transactionID
        ))
    }

    private func setMetadata(key: String, value: String) {
        let records = (try? context.fetch(FetchDescriptor<PersistenceMetadataRecord>())) ?? []
        if let record = records.first(where: { $0.key == key }) {
            record.value = value
            record.updatedAt = .now
        } else {
            context.insert(PersistenceMetadataRecord(key: key, value: value))
        }
    }

    private func pruneRedundantMigrationHistoryIfNeeded() throws {
        let markerKey = "migrationHistoryPruned"
        let metadata = try context.fetch(FetchDescriptor<PersistenceMetadataRecord>())
        guard !metadata.contains(where: { $0.key == markerKey }) else { return }

        let migrationKind = "legacyMigration"
        let transactions = try context.fetch(FetchDescriptor<PersistedMutationTransactionRecord>(
            predicate: #Predicate { $0.kind == migrationKind }
        ))
        guard !transactions.isEmpty else { return }
        let transactionIDs = Set(transactions.map(\.id))
        for operation in try context.fetch(FetchDescriptor<PersistedMutationOperationRecord>())
        where transactionIDs.contains(operation.transactionID) {
            context.delete(operation)
        }
        for event in try context.fetch(FetchDescriptor<PersistedLifecycleEventRecord>())
        where transactionIDs.contains(event.transactionID) {
            context.delete(event)
        }
        for transaction in transactions { context.delete(transaction) }
        context.insert(PersistenceMetadataRecord(key: markerKey, value: "true"))
        try context.save()
    }

    private func lifecycleState(for goal: WeeklyGoal) -> PersistedLifecycleState {
        if goal.isDeleted { return .trashed }
        if goal.isArchived { return .archived }
        return .active
    }

    private func lifecycleState(for task: WeekTask) -> PersistedLifecycleState {
        if task.isDeleted { return .trashed }
        if task.isArchived { return .archived }
        return .active
    }

    private func dayKey(_ date: Date) -> String {
        String(Int(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate))
    }

    private func assignmentKey(taskID: UUID, day: Date) -> String {
        "\(taskID.uuidString):\(dayKey(day))"
    }

    private func normalizedAssignments(
        for task: WeekTask,
        kind _: PersistenceMutationKind
    ) -> [DesiredAssignment] {
        var masks: [Date: Int] = [:]
        if let plannedDate = task.plannedDate {
            masks[calendar.startOfDay(for: plannedDate), default: 0] |= 1
        }
        for date in task.assignedDates {
            masks[calendar.startOfDay(for: date), default: 0] |= 2
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

    private func assignmentSnapshot(_ record: PersistedTaskAssignmentRecord) -> AssignmentSnapshot {
        AssignmentSnapshot(
            taskID: record.taskID,
            day: record.day,
            placementMask: record.placementMask,
            source: record.source,
            originTransactionID: record.originTransactionID
        )
    }
}

private struct AssignmentSnapshot: Codable, Equatable {
    let taskID: UUID
    let day: Date
    let placementMask: Int
    let source: String
    let originTransactionID: UUID?
}

private struct DesiredAssignment {
    let key: String
    let taskID: UUID
    let day: Date
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
