import Foundation

struct WeeklyReviewDayMetric: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let taskMinutes: Int
    let focusMinutes: Int
    let taskChannelMinutes: [String: Int]
    let focusModeMinutes: [String: Int]

    var totalMinutes: Int { taskMinutes + focusMinutes }
}

struct WeeklyReviewChannelMetric: Identifiable, Equatable {
    var id: String { channelID ?? "unassigned" }
    let channelID: String?
    let title: String
    let colorName: String
    let minutes: Int
    let share: Double
}

struct WeeklyReviewFocusMetric: Identifiable, Equatable {
    var id: String { modeID }
    let modeID: String
    let minutes: Int
    let sessionCount: Int
}

struct WeeklyReviewTaskEntry: Identifiable, Equatable {
    var id: WeekTask.ID { task.id }
    let goal: WeeklyGoal
    let task: WeekTask
}

struct WeeklyReviewSnapshot {
    let interval: DateInterval
    let goals: [WeeklyGoal]
    let taskEntries: [WeeklyReviewTaskEntry]
    let completedGoalCount: Int
    let performedTaskCount: Int
    let plannedMinutes: Int
    let actualMinutes: Int
    let channelMetrics: [WeeklyReviewChannelMetric]
    let focusMinutes: [String: Int]
    let focusMetrics: [WeeklyReviewFocusMetric]
    let dayMetrics: [WeeklyReviewDayMetric]
    let incompleteEntries: [WeeklyReviewTaskEntry]
    let dailySummaries: [DailySummary]

    var goalCompletionRate: Double {
        goals.isEmpty ? 0 : Double(completedGoalCount) / Double(goals.count)
    }

    var taskExecutionRate: Double {
        taskEntries.isEmpty ? 0 : Double(performedTaskCount) / Double(taskEntries.count)
    }

    var varianceMinutes: Int { actualMinutes - plannedMinutes }
    var totalFocusMinutes: Int { focusMinutes.values.reduce(0, +) }

    var summaryText: String {
        let varianceDescription: String
        if varianceMinutes == 0 {
            varianceDescription = "与计划一致"
        } else if varianceMinutes > 0 {
            varianceDescription = "比计划多投入 \(varianceMinutes.hourMinuteClockText)"
        } else {
            varianceDescription = "比计划少投入 \((-varianceMinutes).hourMinuteClockText)"
        }
        return "本周完成 \(completedGoalCount) / \(goals.count) 个目标，推进 \(performedTaskCount) / \(taskEntries.count) 项任务。实际投入 \(actualMinutes.hourMinuteClockText)，\(varianceDescription)；专注记录共 \(totalFocusMinutes.hourMinuteClockText)。仍有 \(incompleteEntries.count) 项任务需要后续处理。"
    }

    init(
        goals allGoals: [WeeklyGoal],
        channels: [TaskChannel],
        focusRecords: [FocusRecord],
        dailySummaries allDailySummaries: [DailySummary],
        referenceDate: Date,
        calendar: Calendar = .current
    ) {
        let start = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
            ?? calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let weekInterval = DateInterval(start: start, end: end)

        // The caller provides the exact goal scope and order. Weekly Review
        // uses WeekflowStore.activeGoals so it stays identical to Weekly Planning.
        let weeklyGoals = allGoals

        let weeklyTaskEntries = weeklyGoals.flatMap { goal in
            goal.tasks
                .filter { $0.status != .archived && $0.status != .deleted }
                .map { WeeklyReviewTaskEntry(goal: goal, task: $0) }
        }
        let weeklyCompletedGoalCount = weeklyGoals.filter(Self.isGoalCompleted).count
        let weeklyPerformedTaskCount = weeklyTaskEntries.filter { $0.task.hasExecutionProgress }.count
        let weeklyPlannedMinutes = weeklyTaskEntries.reduce(0) { $0 + $1.task.estimatedMinutes }
        let weeklyActualMinutes = weeklyTaskEntries.reduce(0) { $0 + $1.task.actualMinutes }
        let weeklyIncompleteEntries = weeklyTaskEntries
            .filter { $0.task.status != .completed }
            .sorted { first, second in
                let firstDate = first.task.dueDate ?? first.goal.endDate
                let secondDate = second.task.dueDate ?? second.goal.endDate
                return firstDate < secondDate
            }

        let channelLookup = Dictionary(keepingFirst: channels.map { ($0.id, $0) })
        let channelGroups = Dictionary(grouping: weeklyTaskEntries) { $0.task.channelID }
        let weeklyChannelMetrics: [WeeklyReviewChannelMetric] = channelGroups.compactMap { element in
            let (channelID, entries) = element
            let minutes = entries.reduce(0) { $0 + $1.task.actualMinutes }
            guard minutes > 0 else { return nil }
            return WeeklyReviewChannelMetric(
                channelID: channelID,
                title: channelID.flatMap { channelLookup[$0]?.title } ?? "未分类",
                colorName: channelID.flatMap { channelLookup[$0]?.colorName } ?? "gray",
                minutes: minutes,
                share: weeklyActualMinutes == 0 ? 0 : Double(minutes) / Double(weeklyActualMinutes)
            )
        }
        .sorted { first, second in
            if first.minutes != second.minutes { return first.minutes > second.minutes }
            return first.title < second.title
        }

        let weeklyFocusRecords = focusRecords.filter {
            Self.contains($0.date, in: weekInterval)
        }
        let weeklyFocusGroups = Dictionary(grouping: weeklyFocusRecords, by: \FocusRecord.modeID)
        let weeklyFocusMinutes = weeklyFocusGroups
        .mapValues { records in records.reduce(0) { $0 + $1.minutes } }
        let weeklyFocusMetrics = FocusModePreferences.modes.compactMap { mode -> WeeklyReviewFocusMetric? in
            guard let records = weeklyFocusGroups[mode.id], !records.isEmpty else { return nil }
            return WeeklyReviewFocusMetric(
                modeID: mode.id,
                minutes: records.reduce(0) { $0 + $1.minutes },
                sessionCount: records.reduce(0) { $0 + $1.sessionCount }
            )
        }

        let dayDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let weeklyDayMetrics = dayDates.map { date in
            var taskChannelMinutes: [String: Int] = [:]
            let taskMinutes = weeklyTaskEntries.reduce(0) { partial, entry in
                let minutes = Self.loggedMinutes(
                    for: entry.task,
                    on: date,
                    fallbackDate: referenceDate,
                    interval: weekInterval,
                    calendar: calendar
                )
                if minutes > 0 {
                    taskChannelMinutes[entry.task.channelID ?? "unassigned", default: 0] += minutes
                }
                return partial + minutes
            }
            let focusModeMinutes = Dictionary(grouping: focusRecords.filter {
                calendar.isDate($0.date, inSameDayAs: date)
            }, by: \FocusRecord.modeID)
            .mapValues { records in records.reduce(0) { $0 + $1.minutes } }
            let focusMinutes = focusModeMinutes.values.reduce(0, +)
            return WeeklyReviewDayMetric(
                date: date,
                taskMinutes: taskMinutes,
                focusMinutes: focusMinutes,
                taskChannelMinutes: taskChannelMinutes,
                focusModeMinutes: focusModeMinutes
            )
        }

        let weeklyDailySummaries = allDailySummaries
            .filter { Self.contains($0.date, in: weekInterval) }
            .sorted { $0.date > $1.date }

        interval = weekInterval
        goals = weeklyGoals
        taskEntries = weeklyTaskEntries
        completedGoalCount = weeklyCompletedGoalCount
        performedTaskCount = weeklyPerformedTaskCount
        plannedMinutes = weeklyPlannedMinutes
        actualMinutes = weeklyActualMinutes
        channelMetrics = weeklyChannelMetrics
        focusMinutes = weeklyFocusMinutes
        focusMetrics = weeklyFocusMetrics
        dayMetrics = weeklyDayMetrics
        incompleteEntries = weeklyIncompleteEntries
        dailySummaries = weeklyDailySummaries
    }

    private static func isGoalCompleted(_ goal: WeeklyGoal) -> Bool {
        let visibleTasks = goal.tasks.filter { $0.status != .archived && $0.status != .deleted }
        if !visibleTasks.isEmpty {
            return visibleTasks.allSatisfy { $0.status == .completed }
        }
        return !goal.subgoals.isEmpty && goal.subgoals.allSatisfy(\.isCompleted)
    }

    private static func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }

    private static func loggedMinutes(
        for task: WeekTask,
        on date: Date,
        fallbackDate: Date,
        interval: DateInterval,
        calendar: Calendar
    ) -> Int {
        let timerChanges = task.changeRecords.filter {
            $0.source == .timer
                && $0.field == "实际时间"
                && calendar.isDate($0.date, inSameDayAs: date)
        }
        if !timerChanges.isEmpty {
            return timerChanges.reduce(0) { partial, record in
                let oldMinutes = clockMinutes(record.oldValue)
                let newMinutes = clockMinutes(record.newValue)
                return partial + max(newMinutes - oldMinutes, 0)
            }
        }

        let creditedMinutes = task.completionCredits
            .filter {
                $0.reason == .actualTimeLogged
                    && calendar.isDate($0.date, inSameDayAs: date)
            }
            .compactMap(\.minutes)
            .reduce(0, +)
        if creditedMinutes > 0 { return creditedMinutes }

        guard task.actualMinutes > 0 else { return 0 }
        let recordedDate = task.plannedDate
            ?? task.assignedDates.first(where: { contains($0, in: interval) })
            ?? (contains(task.updatedAt, in: interval) ? task.updatedAt : fallbackDate)
        return calendar.isDate(recordedDate, inSameDayAs: date) ? task.actualMinutes : 0
    }

    private static func clockMinutes(_ value: String) -> Int {
        let components = value.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return 0 }
        return components[0] * 60 + components[1]
    }
}
