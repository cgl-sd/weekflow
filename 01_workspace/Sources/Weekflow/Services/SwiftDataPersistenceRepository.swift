import Foundation
import SwiftData

final class SwiftDataPersistenceRepository: WeekflowPersistenceRepository {
    static let schemaVersion = 2
    static let maximumMutationTransactions = 1_000
    static let mutationRetentionDays = 30

    let storeURL: URL
    private let container: ModelContainer
    private let context: ModelContext
    private let businessCalendar: BusinessCalendar
    private let faultInjector: PersistenceFaultInjector?
    private var transactionNesting = 0

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

    func loadActiveTimerSession() throws -> TaskTimerSession? {
        try loadPayloads(entityType: "activeTimerSession", as: TaskTimerSession.self)?.first
    }

    func saveGoals(_ goals: [WeeklyGoal], kind: PersistenceMutationKind = .userEdit) throws {
        try performTransaction {
            try saveGoalsBody(goals, kind: kind)
        }
    }

    private func saveGoalsBody(
        _ goals: [WeeklyGoal],
        kind: PersistenceMutationKind
    ) throws {
        // Undoable transactions (automatic distribution) store full payloads
        // for rollback; ordinary edits store only entity references (P1-6).
        let needsFullPayload: Bool
        if case .automaticDistribution = kind { needsFullPayload = true }
        else if case .undoAutomaticDistribution = kind { needsFullPayload = true }
        else { needsFullPayload = false }

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
                        after: payload,
                        storeFullPayload: needsFullPayload
                    )
                    recordLifecycleChange(
                        entityType: "goal",
                        entityID: goal.id.uuidString,
                        from: record.lifecycleState,
                        to: lifecycle,
                        transactionID: transaction.id
                    )
                    record.payload = payload
                    record.periodStart = businessCalendar.date(for: goal.startDay)
                    record.periodEnd = businessCalendar.date(for: goal.endDay)
                    record.channelID = goal.channelID
                    record.lifecycleState = lifecycle
                    record.revision += 1
                    record.updatedAt = .now
                }
            } else {
                let record = PersistedGoalRecord(
                    id: goal.id,
                    payload: payload,
                    periodStart: businessCalendar.date(for: goal.startDay),
                    periodEnd: businessCalendar.date(for: goal.endDay),
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
                    after: payload,
                    storeFullPayload: needsFullPayload
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
                taskEnvelope.plannedDay = nil
                taskEnvelope.assignedDays = []
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
                            after: taskPayload,
                            storeFullPayload: needsFullPayload
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
                        after: taskPayload,
                        storeFullPayload: needsFullPayload
                    )
                }
                try faultInjector?(.afterTaskWrite)

                for assignment in normalizedAssignments(for: task, kind: kind) {
                    desiredAssignmentKeys.insert(assignment.key)
                    if let record = assignmentLookup[assignment.key] {
                        let before = try CompactPersistenceCoding.encode(assignmentSnapshot(record))
                        // P0-3 Fix: When automatic distribution modifies an existing
                        // assignment (e.g., mask 1→3), track the transaction ID so
                        // undo can properly restore the previous state.
                        let previousMask = record.placementMask
                        let isAutomaticDistribution: Bool
                        let automaticTransactionID: UUID?
                        if case let .automaticDistribution(transactionID) = kind {
                            isAutomaticDistribution = true
                            automaticTransactionID = transactionID
                        } else {
                            isAutomaticDistribution = false
                            automaticTransactionID = nil
                        }
                        // If automatic distribution is adding the assigned bit (2) to
                        // an existing planned-only assignment, mark it for undo.
                        let shouldTrackForUndo = isAutomaticDistribution
                            && (assignment.placementMask & 2 != 0)
                            && (previousMask & 2 == 0)
                        let updatedSnapshot = AssignmentSnapshot(
                            taskID: assignment.taskID,
                            day: assignment.day,
                            placementMask: assignment.placementMask,
                            source: shouldTrackForUndo ? "automatic" : record.source,
                            originTransactionID: shouldTrackForUndo ? automaticTransactionID : record.originTransactionID
                        )
                        let after = try CompactPersistenceCoding.encode(updatedSnapshot)
                        if before != after {
                            recordOperation(
                                transactionID: transaction.id,
                                sequence: &sequence,
                                entityType: "taskAssignment",
                                entityID: record.id.uuidString,
                                before: before,
                                after: after,
                                storeFullPayload: needsFullPayload
                            )
                            record.day = businessCalendar.date(for: assignment.day)
                            record.placementMask = assignment.placementMask
                            // P0-3 Fix: Update source and originTransactionID for undo tracking
                            if shouldTrackForUndo {
                                record.source = "automatic"
                                record.originTransactionID = automaticTransactionID
                            }
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
                            day: businessCalendar.date(for: assignment.day),
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
                            )),
                            storeFullPayload: needsFullPayload
                        )
                    }
                }
                try faultInjector?(.afterAssignmentWrite)
            }
        }

        for record in existingAssignments where !desiredAssignmentKeys.contains(record.uniquenessKey) {
            recordOperation(
                transactionID: transaction.id,
                sequence: &sequence,
                entityType: "taskAssignment",
                entityID: record.id.uuidString,
                before: try CompactPersistenceCoding.encode(assignmentSnapshot(record)),
                after: nil,
                storeFullPayload: needsFullPayload
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
                after: nil,
                storeFullPayload: needsFullPayload
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
                after: nil,
                storeFullPayload: needsFullPayload
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

    /// Targeted unit-of-work path used for normal interaction. It fetches and
    /// encodes only changed entities; automatic distribution retains its small
    /// assignment-specific undo log while ordinary edits keep no full payload
    /// before/after history.
    func applyGoalChanges(
        _ changes: PersistenceGoalChangeSet,
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        guard !changes.isEmpty else { return }
        try performTransaction {
            let transaction = makeTransaction(kind: kind)
            var sequence = 0

            for goal in changes.goalsToUpsert {
                var descriptor = FetchDescriptor<PersistedGoalRecord>(
                    predicate: #Predicate { $0.id == goal.id }
                )
                descriptor.fetchLimit = 1
                var envelope = goal
                envelope.tasks = []
                let payload = try CompactPersistenceCoding.encode(envelope)
                let lifecycle = lifecycleState(for: goal).rawValue
                if let record = try context.fetch(descriptor).first {
                    record.payload = payload
                    record.periodStart = businessCalendar.date(for: goal.startDay)
                    record.periodEnd = businessCalendar.date(for: goal.endDay)
                    record.channelID = goal.channelID
                    record.lifecycleState = lifecycle
                    record.revision += 1
                    record.updatedAt = .now
                } else {
                    context.insert(PersistedGoalRecord(
                        id: goal.id,
                        payload: payload,
                        periodStart: businessCalendar.date(for: goal.startDay),
                        periodEnd: businessCalendar.date(for: goal.endDay),
                        channelID: goal.channelID,
                        lifecycleState: lifecycle,
                        revision: 1,
                        updatedAt: .now
                    ))
                }
            }
            try faultInjector?(.afterGoalWrite)

            for upsert in changes.tasksToUpsert {
                let task = upsert.task
                var descriptor = FetchDescriptor<PersistedTaskRecord>(
                    predicate: #Predicate { $0.id == task.id }
                )
                descriptor.fetchLimit = 1
                var envelope = task
                envelope.plannedDay = nil
                envelope.assignedDays = []
                let payload = try CompactPersistenceCoding.encode(envelope)
                let lifecycle = lifecycleState(for: task).rawValue
                if let record = try context.fetch(descriptor).first {
                    record.goalID = upsert.goalID
                    record.subgoalID = task.subgoalID
                    record.payload = payload
                    record.channelID = task.channelID
                    record.lifecycleState = lifecycle
                    record.revision += 1
                    record.updatedAt = task.updatedAt
                } else {
                    context.insert(PersistedTaskRecord(
                        id: task.id,
                        goalID: upsert.goalID,
                        subgoalID: task.subgoalID,
                        payload: payload,
                        channelID: task.channelID,
                        lifecycleState: lifecycle,
                        revision: 1,
                        updatedAt: task.updatedAt
                    ))
                }
                try faultInjector?(.afterTaskWrite)

                let taskID = task.id
                let existing = try context.fetch(FetchDescriptor<PersistedTaskAssignmentRecord>(
                    predicate: #Predicate { $0.taskID == taskID }
                ))
                if case let .manualOverride(overriddenTaskID, originalTransactionID) = kind,
                   overriddenTaskID == taskID {
                    for record in existing where record.originTransactionID == originalTransactionID {
                        record.source = "manual"
                        record.originTransactionID = nil
                        record.revision += 1
                    }
                    let remaining = try context.fetch(FetchDescriptor<PersistedTaskAssignmentRecord>(
                        predicate: #Predicate { $0.originTransactionID == originalTransactionID }
                    ))
                    if remaining.isEmpty {
                        var originalDescriptor = FetchDescriptor<PersistedMutationTransactionRecord>(
                            predicate: #Predicate { $0.id == originalTransactionID }
                        )
                        originalDescriptor.fetchLimit = 1
                        if let original = try context.fetch(originalDescriptor).first {
                            original.committedAt = .now
                            original.undoState = "committed"
                        }
                    }
                }
                let lookup = Dictionary(uniqueKeysWithValues: existing.map { ($0.uniquenessKey, $0) })
                let desired = normalizedAssignments(for: task, kind: kind)
                let desiredKeys = Set(desired.map(\.key))
                for assignment in desired {
                    if let record = lookup[assignment.key] {
                        // P0-3 Fix: When undoing automatic distribution, restore
                        // the previous mask and clear the transaction tracking.
                        let previousMask = record.placementMask
                        record.day = businessCalendar.date(for: assignment.day)
                        record.placementMask = assignment.placementMask
                        // If this was an automatic assignment being undone, clear tracking
                        if case .undoAutomaticDistribution = kind,
                           record.originTransactionID != nil {
                            record.source = "manual"
                            record.originTransactionID = nil
                            // Record the undo operation for audit trail
                            recordOperation(
                                transactionID: transaction.id,
                                sequence: &sequence,
                                entityType: "taskAssignment",
                                entityID: record.id.uuidString,
                                before: try CompactPersistenceCoding.encode(AssignmentSnapshot(
                                    taskID: assignment.taskID,
                                    day: assignment.day,
                                    placementMask: previousMask,
                                    source: "automatic",
                                    originTransactionID: record.originTransactionID
                                )),
                                after: try CompactPersistenceCoding.encode(AssignmentSnapshot(
                                    taskID: assignment.taskID,
                                    day: assignment.day,
                                    placementMask: assignment.placementMask,
                                    source: "manual",
                                    originTransactionID: nil
                                )),
                                storeFullPayload: true
                            )
                        }
                        record.revision += 1
                    } else {
                        let origin = kind.transactionID
                        let source = origin == nil ? "manual" : "automatic"
                        let record = PersistedTaskAssignmentRecord(
                            uniquenessKey: assignment.key,
                            taskID: taskID,
                            day: businessCalendar.date(for: assignment.day),
                            placementMask: assignment.placementMask,
                            source: source,
                            originTransactionID: origin
                        )
                        context.insert(record)
                        if origin != nil {
                            recordOperation(
                                transactionID: transaction.id,
                                sequence: &sequence,
                                entityType: "taskAssignment",
                                entityID: record.id.uuidString,
                                before: nil,
                                after: try CompactPersistenceCoding.encode(assignmentSnapshot(record)),
                                storeFullPayload: true
                            )
                        }
                    }
                }
                for record in existing where !desiredKeys.contains(record.uniquenessKey) {
                    if case .undoAutomaticDistribution = kind {
                        recordOperation(
                            transactionID: transaction.id,
                            sequence: &sequence,
                            entityType: "taskAssignment",
                            entityID: record.id.uuidString,
                            before: try CompactPersistenceCoding.encode(assignmentSnapshot(record)),
                            after: nil,
                            storeFullPayload: true
                        )
                    }
                    context.delete(record)
                }
                try faultInjector?(.afterAssignmentWrite)
            }

            for taskID in changes.taskIDsToDelete {
                let assignments = try context.fetch(FetchDescriptor<PersistedTaskAssignmentRecord>(
                    predicate: #Predicate { $0.taskID == taskID }
                ))
                for assignment in assignments { context.delete(assignment) }
                var descriptor = FetchDescriptor<PersistedTaskRecord>(
                    predicate: #Predicate { $0.id == taskID }
                )
                descriptor.fetchLimit = 1
                if let record = try context.fetch(descriptor).first { context.delete(record) }
            }
            for goalID in changes.goalIDsToDelete {
                var descriptor = FetchDescriptor<PersistedGoalRecord>(
                    predicate: #Predicate { $0.id == goalID }
                )
                descriptor.fetchLimit = 1
                if let record = try context.fetch(descriptor).first { context.delete(record) }
            }
            try faultInjector?(.beforeFinalSave)
            try finish(transaction: transaction, operationCount: sequence, kind: kind)
        }
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
        let unique = Dictionary(grouping: states, by: \.day).compactMap { $0.value.last }
        try savePayloads(
            unique,
            entityType: "dailyPlan",
            id: { $0.day.persistenceKey },
            date: { businessCalendar.date(for: $0.day) },
            kind: kind
        )
    }

    func saveFocusRecords(_ records: [FocusRecord], kind: PersistenceMutationKind = .userEdit) throws {
        try savePayloads(
            records,
            entityType: "focusSession",
            id: { $0.id.uuidString },
            date: { businessCalendar.date(for: $0.day) },
            kind: kind
        )
    }

    func saveDailySummaries(_ summaries: [DailySummary], kind: PersistenceMutationKind = .userEdit) throws {
        let unique = Dictionary(grouping: summaries, by: \.day).compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
        try savePayloads(
            unique,
            entityType: "dailyReview",
            id: { $0.day.persistenceKey },
            date: { businessCalendar.date(for: $0.day) },
            kind: kind
        )
    }

    func saveActiveTimerSession(_ session: TaskTimerSession?) throws {
        try savePayloads(
            session.map { [$0] } ?? [],
            entityType: "activeTimerSession",
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
        setMetadata(key: "schemaVersion", value: String(Self.schemaVersion))
        setMetadata(key: "migrationState", value: "complete")
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
        transaction.undoState = "committed"
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

    /// P1-1 Fix: Eagerly normalize all payload records to the current encoding
    /// format. Instead of waiting for each record to be individually edited
    /// (lazy migration), this re-encodes every payload at startup so the
    /// database never contains mixed-format records after a version upgrade.
    /// Returns the number of records that were rewritten.
    @discardableResult
    func normalizeAllPayloads() throws -> Int {
        var rewritten = 0
        // Goal payloads
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
        // Task payloads
        let taskRecords = try context.fetch(FetchDescriptor<PersistedTaskRecord>())
        for record in taskRecords {
            let decoded = try CompactPersistenceCoding.decode(WeekTask.self, from: record.payload)
            var envelope = decoded
            envelope.subtasks = []
            let normalized = try CompactPersistenceCoding.encode(envelope)
            if normalized != record.payload {
                record.payload = normalized
                record.revision += 1
                record.updatedAt = .now
                rewritten += 1
            }
        }
        // Generic payload records (channels, calendar events, etc.)
        let payloadRecords = try context.fetch(FetchDescriptor<PersistedPayloadRecord>())
        for record in payloadRecords {
            // Re-encode raw plist through the current codec envelope.
            // If the codec format changed, the wrapper will differ.
            let rawDecoded = try CompactDataCodec.decode(record.payload)
            let reEncoded = CompactDataCodec.encode(rawDecoded)
            if reEncoded != record.payload {
                record.payload = reEncoded
                record.revision += 1
                record.updatedAt = .now
                rewritten += 1
            }
        }
        if rewritten > 0 { try saveContextOrRollback() }
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
                original.undoState = "undone"
            }
        }
        setMetadata(key: "schemaVersion", value: String(Self.schemaVersion))
        setMetadata(key: "migrationState", value: "native")
        try pruneMutationHistory()
        try saveContextOrRollback()
    }

    /// Records a mutation operation. For ordinary user edits (`storeFullPayload`
    /// = false), only a lightweight entity reference is stored instead of the
    /// complete before/after payload. This prevents unbounded database growth
    /// during normal editing (P1-6 requirement). Undoable operations (automatic
    /// distribution) always store full payloads.
    private func recordOperation(
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
        setMetadata(key: versionKey, value: String(Self.schemaVersion))
        setMetadata(key: "lastMigrationResult", value: "success")
        setMetadata(key: "lastMigrationFailureReason", value: "")
        try saveContextOrRollback()
    }

    private func lifecycleState(for goal: WeeklyGoal) -> PersistedLifecycleState {
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

    private func performTransaction(_ changes: () throws -> Void) throws {
        transactionNesting += 1
        do {
            try changes()
            transactionNesting -= 1
            if transactionNesting == 0 {
                try context.save()
            }
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
                        && $0.undoState == "available"
                )
            },
            now: now,
            maximumCount: Self.maximumMutationTransactions,
            retentionDays: Self.mutationRetentionDays
        )
        guard !removableIDs.isEmpty else { return }

        for operation in try context.fetch(FetchDescriptor<PersistedMutationOperationRecord>())
        where removableIDs.contains(operation.transactionID) {
            context.delete(operation)
        }
        for event in try context.fetch(FetchDescriptor<PersistedLifecycleEventRecord>())
        where removableIDs.contains(event.transactionID) {
            context.delete(event)
        }
        for transaction in transactions where removableIDs.contains(transaction.id) {
            context.delete(transaction)
        }
    }

    private func lifecycleState(for task: WeekTask) -> PersistedLifecycleState {
        if task.isDeleted { return .trashed }
        if task.isArchived { return .archived }
        return .active
    }

    private func dayKey(_ date: Date) -> String {
        businessCalendar.day(containing: date).persistenceKey
    }

    private func assignmentKey(taskID: UUID, day: LocalDay) -> String {
        "\(taskID.uuidString):\(day.persistenceKey)"
    }

    private func normalizedAssignments(
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

    private func assignmentSnapshot(_ record: PersistedTaskAssignmentRecord) -> AssignmentSnapshot {
        AssignmentSnapshot(
            taskID: record.taskID,
            day: assignmentDay(record) ?? businessCalendar.day(containing: record.day),
            placementMask: record.placementMask,
            source: record.source,
            originTransactionID: record.originTransactionID
        )
    }

    private func assignmentDay(_ record: PersistedTaskAssignmentRecord) -> LocalDay? {
        guard let separator = record.uniquenessKey.lastIndex(of: ":") else {
            return businessCalendar.day(containing: record.day)
        }
        let key = String(record.uniquenessKey[record.uniquenessKey.index(after: separator)...])
        return (try? LocalDay(persistenceKey: key)) ?? businessCalendar.day(containing: record.day)
    }
}

private struct AssignmentSnapshot: Codable, Equatable {
    let taskID: UUID
    let day: LocalDay
    let placementMask: Int
    let source: String
    let originTransactionID: UUID?
}

private struct DesiredAssignment {
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
