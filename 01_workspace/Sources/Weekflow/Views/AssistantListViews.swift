import SwiftUI

struct AssistantGoalsView: View {
    @Bindable var store: WeekflowStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Date.weekRangeLabel).foregroundStyle(WeekflowPalette.secondaryText)
            ForEach(store.activeGoals) { goal in
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.title).lineLimit(2)
                    WeekflowDailyProgressTrack(
                        fraction: goal.progress,
                        hasProgress: goal.progress > 0,
                        alwaysVisible: true,
                        accessibilityLabel: "周目标完成进度",
                        accessibilityValue: "已完成 \(Int(goal.progress * 100))%"
                    )
                    .frame(height: WeekflowLayout.homeDailyProgressHeight)
                }
            }
            Spacer()
        }
    }
}

struct AssistantBacklogView: View {
    @Bindable var store: WeekflowStore
    let openTask: ((goal: WeeklyGoal, task: WeekTask)) -> Void

    var body: some View {
        AssistantTaskCardList(
            entries: store.taskPool,
            store: store,
            emptyTitle: "待办箱为空",
            openTask: openTask
        )
    }
}

struct AssistantShutdownView: View {
    @Bindable var store: WeekflowStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                archiveMetricStrip
                Divider()
                Text("今日成果")
                    .font(.system(size: 12, weight: .semibold))
                if completedToday.isEmpty {
                    Text("今天还没有完成任务")
                        .font(.system(size: 11))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                } else {
                    ForEach(completedToday, id: \.task.id) { entry in
                        Label(entry.task.title, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(WeekflowPalette.textPrimary)
                            .lineLimit(2)
                    }
                }
                Divider()
                Text("今日重点")
                    .font(.system(size: 12, weight: .semibold))
                Text(store.dailySummary(on: .now)?.content.nonEmpty ?? "每日回顾完成后，重点内容会整理在这里。")
                    .font(.system(size: 11))
                    .foregroundStyle(WeekflowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var completedToday: [(goal: WeeklyGoal, task: WeekTask)] {
        store.todayTasks.filter { $0.task.status == .completed }
    }

    private var focusSessionsToday: Int {
        store.focusRecords
            .filter { SystemBusinessCalendar.current.calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.sessionCount }
    }

    private var timedTasksToday: Int {
        store.todayTasks.filter { $0.task.actualMinutes > 0 }.count
    }

    private var archiveMetricStrip: some View {
        HStack(spacing: 6) {
            archiveMetric(value: "\(completedToday.count)", label: "完成")
            archiveMetric(value: "\(focusSessionsToday)", label: "专注")
            archiveMetric(value: "\(timedTasksToday)", label: "计时")
        }
    }

    private func archiveMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 9.5)).foregroundStyle(WeekflowPalette.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(WeekflowPalette.surfaceHover, in: WeekflowRoundedRectangle(cornerRadius: 7))
    }
}

struct AssistantTaskCardList: View {
    let entries: [(goal: WeeklyGoal, task: WeekTask)]
    @Bindable var store: WeekflowStore
    let emptyTitle: String
    let openTask: ((goal: WeeklyGoal, task: WeekTask)) -> Void

    var body: some View {
        if entries.isEmpty {
            Text(emptyTitle)
                .font(.system(size: 11.5))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(spacing: WeekflowLayout.homeTaskCardSpacing) {
                    ForEach(entries, id: \.task.id) { entry in
                        SunsamaTaskCard(
                            entry: entry,
                            store: store,
                            dragSourceDate: entry.task.plannedDate,
                            inferredStartTime: nil,
                            compactHeight: WeekflowLayout.homeTaskCardHeight,
                            openTask: { openTask(entry) }
                        )
                    }
                }
            }
            .scrollIndicators(.visible)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
