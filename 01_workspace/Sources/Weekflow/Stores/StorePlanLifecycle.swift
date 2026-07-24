import Foundation
import Observation

// Plan CRUD, lifecycle transitions (create / archive / query).

extension WeekflowStore {
    /// Creates a new planning period and selects it as active.
    @discardableResult
    func addPlan(title: String, startDate: Date, endDate: Date) -> UUID {
        let sortOrder = (plans.map(\.sortOrder).min() ?? 0) - 1
        let plan = WeeklyPlan(
            title: title,
            startDate: startDate,
            endDate: endDate,
            sortOrder: sortOrder
        )
        plans.insert(plan, at: 0)
        persistPlans()
        return plan.id
    }

    /// Archives a plan and all goals associated with it.
    func archivePlan(id: UUID) {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return }
        plans[index].archivedAt = .now
        // Batch-archive all goals belonging to this plan.
        for goalIndex in goals.indices where goals[goalIndex].planID == id {
            if goals[goalIndex].archivedAt == nil && goals[goalIndex].deletedAt == nil {
                goals[goalIndex].archivedAt = .now
            }
        }
        invalidateGoalIndex()
        persistPlans()
        persist()
    }

    /// Returns all goals associated with a specific plan.
    func goalsForPlan(_ planID: UUID) -> [WeeklyGoal] {
        goals.filter { $0.planID == planID && !$0.isDeleted }
    }

    /// Persists the plans array to local storage.
    func persistPlans() {
        guard persistenceEnabled else { return }
        do {
            try storage.savePlans(plans)
        } catch {
            persistenceEnabled = false
            persistenceIssue = "规划保存失败：\(error.localizedDescription)"
        }
    }

    /// Restores an archived plan (un-archives it and its goals).
    func restorePlan(id: UUID) {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return }
        plans[index].archivedAt = nil
        // Also restore goals that were archived with this plan
        for goalIndex in goals.indices where goals[goalIndex].planID == id {
            if goals[goalIndex].archivedAt != nil && goals[goalIndex].deletedAt == nil {
                goals[goalIndex].archivedAt = nil
            }
        }
        invalidateGoalIndex()
        persistPlans()
        persist()
    }

    /// Soft-deletes a plan (moves to trash).
    func deletePlan(id: UUID) {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return }
        plans[index].deletedAt = .now
        persistPlans()
    }

    /// Permanently removes a plan from the store.
    func permanentlyDeletePlan(id: UUID) {
        plans.removeAll { $0.id == id }
        persistPlans()
    }

    /// Permanently deletes all plans in trash.
    func permanentlyDeleteAllDeletedPlans() {
        plans.removeAll { $0.isDeleted }
        persistPlans()
    }
}
