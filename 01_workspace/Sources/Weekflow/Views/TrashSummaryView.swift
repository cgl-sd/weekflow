import SwiftUI

struct TrashSummaryView: View {
    @Bindable var store: WeekflowStore
    let selectedChannelID: String
    let openTask: (((goal: WeeklyGoal, task: WeekTask)) -> Void)?
    @State private var tasksExpanded = true
    @State private var goalsExpanded = true
    @State private var searchText = ""
    @State private var isConfirmingDeleteAllTasks = false
    @State private var isConfirmingDeleteAllGoals = false
    @FocusState private var isSearchFocused: Bool

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

                searchField

                ArchiveDisclosureSection(
                    title: "已删除的任务",
                    count: filteredTasks.count,
                    isExpanded: $tasksExpanded,
                    trailingAction: {
                        if !filteredTasks.isEmpty {
                            deleteAllButton(
                                isConfirming: $isConfirmingDeleteAllTasks,
                                action: { store.permanentlyDeleteAllDeletedTasks() }
                            )
                        }
                    }
                ) {
                    if filteredTasks.isEmpty {
                        ArchiveEmptyRow(text: searchText.isEmpty ? "当前筛选下没有已删除任务" : "没有匹配的任务")
                    } else {
                        ForEach(filteredTasks, id: \.task.id) { entry in
                            TrashTaskCard(store: store, entry: entry, openTask: openTask)
                        }
                    }
                }

                ArchiveDisclosureSection(
                    title: "已删除的目标",
                    count: filteredGoals.count,
                    isExpanded: $goalsExpanded,
                    trailingAction: {
                        if !filteredGoals.isEmpty {
                            deleteAllButton(
                                isConfirming: $isConfirmingDeleteAllGoals,
                                action: { store.permanentlyDeleteAllDeletedGoals() }
                            )
                        }
                    }
                ) {
                    if filteredGoals.isEmpty {
                        ArchiveEmptyRow(text: searchText.isEmpty ? "当前筛选下没有已删除周目标" : "没有匹配的目标")
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WeekflowPalette.textMuted)
            TextField("搜索已删除的内容…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: isSearchFocused ? .medium : .regular))
                .foregroundStyle(isSearchFocused ? WeekflowPalette.textPrimary : .primary)
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                WeekflowButton { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WeekflowPalette.surface.opacity(0.6), in: WeekflowRoundedRectangle(cornerRadius: 8))
        .overlay(
            WeekflowRoundedRectangle(cornerRadius: 8)
                .stroke(WeekflowPalette.border.opacity(0.5))
        )
    }

    @ViewBuilder
    private func deleteAllButton(isConfirming: Binding<Bool>, action: @escaping () -> Void) -> some View {
        DeleteAllCapsuleButton(isConfirming: isConfirming, action: action)
    }

    private var filteredTasks: [(goal: WeeklyGoal, task: WeekTask)] {
        store.deletedTasks.filter { entry in
            matchesChannel(entry.task.channelID) && matchesSearch(entry.task.title)
        }
    }

    private var filteredGoals: [WeeklyGoal] {
        store.deletedGoals.filter { goal in
            let channelMatch = selectedChannelID == "all"
                || matchesChannel(goal.channelID)
                || goal.tasks.contains { matchesChannel($0.channelID) }
            return channelMatch && matchesSearch(goal.title)
        }
    }

    private func matchesChannel(_ channelID: String?) -> Bool {
        ArchiveChannelFilter.matches(channelID: channelID, selectedChannelID: selectedChannelID)
    }

    private func matchesSearch(_ title: String) -> Bool {
        searchText.isEmpty || title.localizedCaseInsensitiveContains(searchText)
    }
}

struct TrashTaskCard: View {
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

struct TrashGoalCard: View {
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

/// “全部删除”胶囊按钮：悬浮高亮 + 两步确认 + 点击外部取消
struct DeleteAllCapsuleButton: View {
    @Binding var isConfirming: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        WeekflowButton {
            if isConfirming {
                action()
                withAnimation(.easeInOut(duration: 0.15)) { isConfirming = false }
            } else {
                withAnimation(.easeInOut(duration: 0.15)) { isConfirming = true }
            }
        } label: {
            Text(isConfirming ? "确认删除" : "全部删除")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isConfirming ? WeekflowPalette.danger : WeekflowPalette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isConfirming
                        ? WeekflowPalette.danger.opacity(0.12)
                        : (isHovered ? WeekflowPalette.surfaceHover : WeekflowPalette.surfaceHover.opacity(0.5)),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        isConfirming
                            ? WeekflowPalette.danger.opacity(0.4)
                            : (isHovered ? WeekflowPalette.border : .clear),
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .background {
            if isConfirming {
                GeometryReader { proxy in
                    WindowOutsideClickMonitor(
                        protectedRect: CGRect(origin: .zero, size: proxy.size),
                        monitoredEventMask: .leftMouseDown,
                        action: cancelConfirmation
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isConfirming)
    }

    private func cancelConfirmation() {
        guard isConfirming else { return }
        withAnimation(.easeInOut(duration: 0.15)) { isConfirming = false }
    }
}
