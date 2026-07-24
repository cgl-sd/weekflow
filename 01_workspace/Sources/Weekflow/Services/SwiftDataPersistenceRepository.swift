import Foundation
import SwiftData

final class SwiftDataPersistenceRepository: WeekflowPersistenceRepository {
    static let schemaVersion = 2
    static let maximumMutationTransactions = 1_000
    static let mutationRetentionDays = 30
    /// P2 fix: minimum interval between mutation history prune passes.
    /// Pruning scans all transactions/operations; doing it every single write
    /// is wasteful. At most once every 5 minutes is sufficient.
    static let pruneIntervalSeconds: TimeInterval = 300

    let storeURL: URL
    let container: ModelContainer
    let context: ModelContext
    let businessCalendar: BusinessCalendar
    let faultInjector: PersistenceFaultInjector?
    var transactionNesting = 0
    /// P2 fix: timestamp of the last mutation history prune pass.
    var lastPruneAt: Date?

    init(
        storeURL: URL,
        calendar: Calendar = SystemBusinessCalendar.current.calendar,
        faultInjector: PersistenceFaultInjector? = nil
    ) throws {
        self.storeURL = storeURL
        businessCalendar = BusinessCalendar(calendar: calendar)
        self.faultInjector = faultInjector
        let schema = Schema(versionedSchema: WeekflowSchemaV2.self)
        let configuration = ModelConfiguration(
            "Weekflow",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(
            for: schema,
            migrationPlan: WeekflowMigrationPlan.self,
            configurations: [configuration]
        )
        context = ModelContext(container)
        context.autosaveEnabled = false
        try recordSuccessfulSchemaMigrationIfNeeded()
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
                    task.plannedDay = assignments.first(where: { $0.placementMask & 1 != 0 })
                        .flatMap(assignmentDay)
                    task.assignedDays = assignments
                        .filter { $0.placementMask & 2 != 0 }
                        .compactMap(assignmentDay)
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
        try loadPayloads(entityType: PersistenceEntity.channel, as: TaskChannel.self)
    }

    func loadCalendarEvents() throws -> [CalendarEvent]? {
        try loadPayloads(entityType: PersistenceEntity.calendarEvent, as: CalendarEvent.self)
    }

    func loadDailyPlanningStates() throws -> [DailyPlanningState]? {
        let values = try loadPayloads(entityType: PersistenceEntity.dailyPlan, as: DailyPlanningState.self)
        return values?.sorted { $0.date < $1.date }
    }

    func loadFocusRecords() throws -> [FocusRecord]? {
        let values = try loadPayloads(entityType: PersistenceEntity.focusSession, as: FocusRecord.self)
        return values?.sorted { $0.date < $1.date }
    }

    func loadDailySummaries() throws -> [DailySummary]? {
        let values = try loadPayloads(entityType: PersistenceEntity.dailyReview, as: DailySummary.self)
        return values?.sorted { $0.date < $1.date }
    }

    func loadActiveTimerSession() throws -> TaskTimerSession? {
        try loadPayloads(entityType: PersistenceEntity.activeTimerSession, as: TaskTimerSession.self)?.first
    }

    func saveChannels(_ channels: [TaskChannel], kind: PersistenceMutationKind = .userEdit) throws {
        try savePayloads(
            channels,
            entityType: PersistenceEntity.channel,
            id: { $0.id },
            date: { $0.archivedAt },
            kind: kind
        )
    }

    func saveCalendarEvents(_ events: [CalendarEvent], kind: PersistenceMutationKind = .userEdit) throws {
        try savePayloads(events, entityType: PersistenceEntity.calendarEvent, id: { $0.id.uuidString }, date: { $0.startDate }, kind: kind)
    }

    func saveDailyPlanningStates(_ states: [DailyPlanningState], kind: PersistenceMutationKind = .userEdit) throws {
        let unique = Dictionary(grouping: states, by: \.day).compactMap { $0.value.last }
        try savePayloads(
            unique,
            entityType: PersistenceEntity.dailyPlan,
            id: { $0.day.persistenceKey },
            date: { businessCalendar.date(for: $0.day) },
            kind: kind
        )
    }

    func saveFocusRecords(_ records: [FocusRecord], kind: PersistenceMutationKind = .userEdit) throws {
        try savePayloads(
            records,
            entityType: PersistenceEntity.focusSession,
            id: { $0.id.uuidString },
            date: { businessCalendar.date(for: $0.day) },
            kind: kind
        )
    }

    func saveDailySummaries(_ summaries: [DailySummary], kind: PersistenceMutationKind = .userEdit) throws {
        let unique = Dictionary(grouping: summaries, by: \.day).compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
        try savePayloads(
            unique,
            entityType: PersistenceEntity.dailyReview,
            id: { $0.day.persistenceKey },
            date: { businessCalendar.date(for: $0.day) },
            kind: kind
        )
    }

    func saveActiveTimerSession(_ session: TaskTimerSession?) throws {
        try savePayloads(
            session.map { [$0] } ?? [],
            entityType: PersistenceEntity.activeTimerSession,
            id: { _ in "current" },
            date: { $0.lastCheckpointAt },
            kind: .userEdit
        )
    }

    func importLegacySnapshot(_ snapshot: WeekflowPersistenceSnapshot) throws {
        try saveGoals(snapshot.goals, kind: .migration)
        try saveChannels(snapshot.channels, kind: .migration)
        try saveCalendarEvents(snapshot.calendarEvents, kind: .migration)
        try saveDailyPlanningStates(snapshot.dailyPlanningStates, kind: .migration)
        try saveFocusRecords(snapshot.focusRecords, kind: .migration)
        try saveDailySummaries(snapshot.dailySummaries, kind: .migration)
        try saveActiveTimerSession(snapshot.activeTimerSession)
        try setMetadata(key: "schemaVersion", value: String(Self.schemaVersion))
        try setMetadata(key: "migrationState", value: "complete")
        try saveContextOrRollback()
    }

    func saveApplicationSnapshot(
        _ snapshot: WeekflowPersistenceSnapshot,
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        try performTransaction {
            try faultInjector?(.beforeFirstWrite)
            try saveGoals(snapshot.goals, kind: kind)
            try faultInjector?(.afterGoalWrite)
            try saveChannels(snapshot.channels, kind: kind)
            try saveCalendarEvents(snapshot.calendarEvents, kind: kind)
            try faultInjector?(.afterCalendarEventWrite)
            try saveDailyPlanningStates(snapshot.dailyPlanningStates, kind: kind)
            try faultInjector?(.afterDailyPlanWrite)
            try saveFocusRecords(snapshot.focusRecords, kind: kind)
            try saveDailySummaries(snapshot.dailySummaries, kind: kind)
            try saveActiveTimerSession(snapshot.activeTimerSession)
            try faultInjector?(.beforeFinalSave)
        }
    }

    func saveDailyPlanAndCalendarEvents(
        states: [DailyPlanningState],
        events: [CalendarEvent],
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        try performTransaction {
            try faultInjector?(.beforeFirstWrite)
            try saveDailyPlanningStates(states, kind: kind)
            try faultInjector?(.afterDailyPlanWrite)
            try saveCalendarEvents(events, kind: kind)
            try faultInjector?(.afterCalendarEventWrite)
            try faultInjector?(.beforeFinalSave)
        }
    }

    func saveGoalChangesAndActiveTimer(
        changes: PersistenceGoalChangeSet,
        session: TaskTimerSession?,
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        try performTransaction {
            if !changes.isEmpty { try applyGoalChanges(changes, kind: kind) }
            try saveActiveTimerSession(session)
            try faultInjector?(.beforeFinalSave)
        }
    }

    func pendingAutomaticDistributionChanges() throws -> [PersistedAutomaticDistributionChange] {
        let automaticKind = "automaticDistribution"
        let availableState = PersistenceUndoState.available
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
        let taskGoalLookup = Dictionary(keepingFirst:
            try context.fetch(FetchDescriptor<PersistedTaskRecord>()).map { ($0.id, $0.goalID) }
        )
        return assignments.compactMap { assignment in
            guard let goalID = taskGoalLookup[assignment.taskID] else { return nil }
            return PersistedAutomaticDistributionChange(
                transactionID: transaction.id,
                goalID: goalID,
                taskID: assignment.taskID,
                assignedDate: businessCalendar.date(for: assignmentDay(assignment) ?? businessCalendar.day(containing: assignment.day))
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
        transaction.undoState = PersistenceUndoState.committed
        try saveContextOrRollback()
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
                entityType: PersistenceEntity.taskAssignment,
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
                original.undoState = PersistenceUndoState.committed
            }
        }
        try finish(transaction: mutation, operationCount: sequence, kind: .userEdit)
    }

    /// P1-1 Fix: Eagerly normalize all payload records to the current encoding
    /// format. Instead of waiting for each record to be individually edited
    /// (lazy migration), this re-encodes every payload at startup so the
    /// database never contains mixed-format records after a version upgrade.
    /// Returns the number of records that were rewritten.
    @discardableResult
    func normalizeAllPayloads() throws -> Int {
        try performTransaction { try normalizeAllPayloadsBody() }
    }

    @discardableResult
    func normalizeAllPayloadsIfNeeded(marker: String) throws -> Int {
        try performTransaction {
            let metadata = try context.fetch(FetchDescriptor<PersistenceMetadataRecord>())
            guard !metadata.contains(where: { $0.key == marker && $0.value == "complete" }) else {
                return 0
            }
            let rewritten = try normalizeAllPayloadsBody()
            try setMetadata(key: marker, value: "complete")
            return rewritten
        }
    }

    private func normalizeAllPayloadsBody() throws -> Int {
        try faultInjector?(.duringNormalization)
        var rewritten = 0
        let goalRecords = try context.fetch(FetchDescriptor<PersistedGoalRecord>())
        for record in goalRecords {
            let decoded = try CompactPersistenceCoding.decode(WeeklyGoal.self, from: record.payload)
            var envelope = decoded
            envelope.tasks = []
            let normalized = try CompactPersistenceCoding.encode(envelope)
            if normalized != record.payload {
                record.payload = normalized
                record.revision += 1
                record.updatedAt = .now
                rewritten += 1
            }
        }
        let taskRecords = try context.fetch(FetchDescriptor<PersistedTaskRecord>())
        for record in taskRecords {
            let decoded = try CompactPersistenceCoding.decode(WeekTask.self, from: record.payload)
            var envelope = decoded
            envelope.plannedDay = nil
            envelope.assignedDays = []
            let normalized = try CompactPersistenceCoding.encode(envelope)
            if normalized != record.payload {
                record.payload = normalized
                record.revision += 1
                record.updatedAt = .now
                rewritten += 1
            }
        }
        let payloadRecords = try context.fetch(FetchDescriptor<PersistedPayloadRecord>())
        for record in payloadRecords {
            let rawDecoded = try CompactDataCodec.decode(record.payload)
            let reEncoded = CompactDataCodec.encode(rawDecoded)
            if reEncoded != record.payload {
                record.payload = reEncoded
                record.revision += 1
                record.updatedAt = .now
                rewritten += 1
            }
        }
        return rewritten
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
        let cleanupCutoff = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -Self.mutationRetentionDays,
            to: .now
        ) ?? .distantPast
        let ordinaryTransactions = transactions.filter { $0.kind == PersistenceMutationKind.userEdit.title }
        let cleanableCount = ordinaryTransactions.filter { $0.createdAt < cleanupCutoff }.count
            + max(ordinaryTransactions.count - Self.maximumMutationTransactions, 0)
        return PersistenceDiagnostics(
            goalCount: goals.count,
            taskCount: tasks.count,
            assignmentCount: assignments.count,
            transactionCount: transactions.count,
            operationCount: operations.count,
            payloadByteCount: goalBytes + taskBytes + otherPayloadBytes + operationBytes,
            historyByteCount: operationBytes,
            oldestTransactionDate: transactions.map(\.createdAt).min(),
            cleanableTransactionCount: min(cleanableCount, ordinaryTransactions.count)
        )
    }

    func makeTransaction(kind: PersistenceMutationKind) -> PersistedMutationTransactionRecord {
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

    func finish(
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
            try saveContextOrRollback()
            return
        }
        guard operationCount > 0 else {
            context.delete(transaction)
            return
        }
        if case let .undoAutomaticDistribution(originalID) = kind {
            let transactions = try context.fetch(FetchDescriptor<PersistedMutationTransactionRecord>())
            if let original = transactions.first(where: { $0.id == originalID }) {
                original.undoState = PersistenceUndoState.undone
            }
        }
        try setMetadata(key: "schemaVersion", value: String(Self.schemaVersion))
        try setMetadata(key: "migrationState", value: "native")
        // P2 fix: throttle prune to at most once every pruneIntervalSeconds.
        let now = Date.now
        if lastPruneAt == nil || now.timeIntervalSince(lastPruneAt!) >= Self.pruneIntervalSeconds {
            try pruneMutationHistory(now: now)
            lastPruneAt = now
        }
        try saveContextOrRollback()
    }

    /// Records a mutation operation. For ordinary user edits (`storeFullPayload`
    /// = false), only a lightweight entity reference is stored instead of the
    /// complete before/after payload. This prevents unbounded database growth
    /// during normal editing (P1-6 requirement). Undoable operations (automatic
    /// distribution) always store full payloads.
    func recordOperation(
        transactionID: UUID,
        sequence: inout Int,
        entityType: String,
        entityID: String,
        before: Data?,
        after: Data?,
        storeFullPayload: Bool = false
    ) {
        // For ordinary edits, store only the entity reference (type + ID) to
        // keep the mutation log compact. Full payloads are reserved for
        // undoable transactions like automatic distribution.
        let storedBefore: Data? = storeFullPayload ? before : nil
        let storedAfter: Data? = storeFullPayload ? after : nil
        context.insert(PersistedMutationOperationRecord(
            transactionID: transactionID,
            sequence: sequence,
            entityType: entityType,
            entityID: entityID,
            beforeValue: storedBefore,
            afterValue: storedAfter
        ))
        sequence += 1
    }

    func recordLifecycleChange(
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

    /// Reads and updates a metadata record. Throws on fetch failure (Phase 2-1
    /// fix): previously a failed fetch was coerced to `[]` via `try?`, which turned
    /// a real database error into a spurious "insert new record" path — masking the
    /// error and risking a unique-key conflict on save. Propagating the error lets it
    /// flow into the unified rollback / protection-mode handling.
    private func setMetadata(key: String, value: String) throws {
        let records = try context.fetch(FetchDescriptor<PersistenceMetadataRecord>())
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
        try saveContextOrRollback()
    }

    private func recordSuccessfulSchemaMigrationIfNeeded() throws {
        let versionKey = "currentSchemaVersion"
        let metadata = try context.fetch(FetchDescriptor<PersistenceMetadataRecord>())
        let previousVersion = metadata.first(where: { $0.key == versionKey })
            .flatMap { Int($0.value) } ?? 1
        guard previousVersion != Self.schemaVersion else { return }

        context.insert(PersistedMigrationAuditRecord(
            fromVersion: previousVersion,
            toVersion: Self.schemaVersion,
            result: "success"
        ))
        try setMetadata(key: versionKey, value: String(Self.schemaVersion))
        try setMetadata(key: "lastMigrationResult", value: "success")
        try setMetadata(key: "lastMigrationFailureReason", value: "")
        try saveContextOrRollback()
    }

    func lifecycleState(for goal: WeeklyGoal) -> PersistedLifecycleState {
        if goal.isDeleted { return .trashed }
        if goal.isArchived { return .archived }
        return .active
    }

    private func saveContextOrRollback() throws {
        guard transactionNesting == 0 else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    func performTransaction<Result>(_ changes: () throws -> Result) throws -> Result {
        transactionNesting += 1
        do {
            let result = try changes()
            transactionNesting -= 1
            if transactionNesting == 0 {
                try context.save()
            }
            return result
        } catch {
            transactionNesting = max(transactionNesting - 1, 0)
            context.rollback()
            throw error
        }
    }

    private func pruneMutationHistory(now: Date = .now) throws {
        let transactions = try context.fetch(FetchDescriptor<PersistedMutationTransactionRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        let removableIDs = MutationHistoryRetentionPolicy.removableIDs(
            from: transactions.map {
                MutationHistoryCandidate(
                    id: $0.id,
                    kind: $0.kind,
                    createdAt: $0.createdAt,
                    isUndoable: $0.kind == PersistenceMutationKind.automaticDistribution(transactionID: $0.id).title
                        && $0.undoState == PersistenceUndoState.available
                )
            },
            now: now,
            maximumCount: Self.maximumMutationTransactions,
            retentionDays: Self.mutationRetentionDays
        )
        guard !removableIDs.isEmpty else { return }

        // Phase 3-5 fix: push the transactionID filter into the fetch predicate so
        // we only load the operations/events we will actually delete, instead of
        // fetching every row of both tables and filtering in memory (which spiked
        // as the mutation log grew).
        let removableIDArray = Array(removableIDs)
        let removableOperations = try context.fetch(FetchDescriptor<PersistedMutationOperationRecord>(
            predicate: #Predicate { removableIDArray.contains($0.transactionID) }
        ))
        for operation in removableOperations {
            context.delete(operation)
        }
        let removableEvents = try context.fetch(FetchDescriptor<PersistedLifecycleEventRecord>(
            predicate: #Predicate { removableIDArray.contains($0.transactionID) }
        ))
        for event in removableEvents {
            context.delete(event)
        }
        for transaction in transactions where removableIDs.contains(transaction.id) {
            context.delete(transaction)
        }
    }

    func lifecycleState(for task: WeekTask) -> PersistedLifecycleState {
        if task.isDeleted { return .trashed }
        if task.isArchived { return .archived }
        return .active
    }

    private func dayKey(_ date: Date) -> String {
        businessCalendar.day(containing: date).persistenceKey
    }

    func assignmentKey(taskID: UUID, day: LocalDay) -> String {
        "\(taskID.uuidString):\(day.persistenceKey)"
    }
}
