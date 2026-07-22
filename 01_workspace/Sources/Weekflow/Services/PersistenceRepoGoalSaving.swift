import Foundation
import SwiftData

extension SwiftDataPersistenceRepository {
    func saveGoals(_ goals: [WeeklyGoal], kind: PersistenceMutationKind = .userEdit) throws {
        try performTransaction {
            try saveGoalsBody(goals, kind: kind)
        }
    }

    func saveGoalsBody(
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

}
