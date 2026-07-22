import SwiftUI

struct TrashSummaryView: View {
    @Bindable var store: WeekflowStore
    let selectedChannelID: String
    let openTask: (((goal: WeeklyGoal, task: WeekTask)) -> Void)?
    @State private var tasksExpanded = true
    @State private var goalsExpanded = true

    init(
        store: WeekflowStore,
        selectedChannelID: String = "all",
        openTask: (((goal: WeeklyGoal, task: WeekTask)) -> Void)? = nil
    ) {
        self.store = store
        self.selectedChannelID = selectedChannelID
        self.openTask = openTask
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("可恢复；彻底删除后无法找回。")
                    .font(.system(size: 13))
                    .foregroundStyle(WeekflowPalette.textSecondary)

                ArchiveDisclosureSection(
                    title: "已删除的任务",
                    count: filteredTasks.count,
                    isExpanded: $tasksExpanded
                ) {
                    if filteredTasks.isEmpty {
                        ArchiveEmptyRow(text: "当前筛选下没有已删除任务")
                    } else {
                        ForEach(filteredTasks, id: \.task.id) { entry in
                            TrashTaskCard(store: store, entry: entry, openTask: openTask)
                        }
                    }
                }

                ArchiveDisclosureSection(
                    title: "已删除的目标",
                    count: filteredGoals.count,
                    isExpanded: $goalsExpanded
                ) {
                    if filteredGoals.isEmpty {
                        ArchiveEmptyRow(text: "当前筛选下没有已删除周目标")
                    } else {
                        ForEach(filteredGoals) { goal in
                            TrashGoalCard(store: store, goal: goal)
                        }
                    }
                }
            }
            .padding(28)
            .padding(.trailing, WeekflowLayout.scrollbarGutterWidth)
            .frame(maxWidth: 1_040, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)
    }

    private var filteredTasks: [(goal: WeeklyGoal, task: WeekTask)] {
        store.deletedTasks.filter { matchesChannel($0.task.channelID) }
    }

    private var filteredGoals: [WeeklyGoal] {
        store.deletedGoals.filter { goal in
            selectedChannelID == "all"
                || matchesChannel(goal.channelID)
                || goal.tasks.contains { matchesChannel($0.channelID) }
        }
    }

    private func matchesChannel(_ channelID: String?) -> Bool {
        ArchiveChannelFilter.matches(channelID: channelID, selectedChannelID: selectedChannelID)
    }
}

private struct TrashTaskCard: View {
    @Bindable var store: WeekflowStore
    let entry: (goal: WeeklyGoal, task: WeekTask)
    let openTask: (((goal: WeeklyGoal, task: WeekTask)) -> Void)?

    var body: some View {
        ArchiveItemCard(symbol: "trash") {
            WeekflowButton { openTask?(entry) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text("删除于 \(entry.task.updatedAt.dayLabel)")
                        if let channel = store.channel(for: entry.task.channelID) {
                            Text("·")
                            Label(channel.title, systemImage: channel.resolvedIconName)
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeekflowPalette.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } actions: {
            ArchiveCapsuleActions(
                destructiveTitle: "删除",
                requiresDestructiveConfirmation: true,
                restore: {
                    store.restoreDeletedTask(goalID: entry.goal.id, taskID: entry.task.id)
                },
                destructive: {
                    store.permanentlyDeleteTask(goalID: entry.goal.id, taskID: entry.task.id)
                }
            )
        }
    }
}

private struct TrashGoalCard: View {
    @Bindable var store: WeekflowStore
    let goal: WeeklyGoal

    var body: some View {
        let completed = goal.subgoals.filter(\.isCompleted).count
        ArchiveItemCard(symbol: "trash") {
            VStack(alignment: .leading, spacing: 5) {
                Text(goal.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(1)
                Text("删除于 \((goal.deletedAt ?? .now).dayLabel) · \(completed) 个子目标已完成")
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeekflowPalette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            ArchiveCapsuleActions(
                destructiveTitle: "删除",
                requiresDestructiveConfirmation: true,
                restore: {
                    store.restoreDeletedGoal(id: goal.id)
                },
                destructive: {
                    store.permanentlyDeleteGoal(id: goal.id)
                }
            )
        }
    }
}
