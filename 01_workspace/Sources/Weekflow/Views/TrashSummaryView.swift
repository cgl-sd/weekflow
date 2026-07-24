import SwiftUI

struct TrashSummaryView: View {
    @Bindable var store: WeekflowStore
    let selectedChannelID: String
    let openTask: (((goal: WeeklyGoal, task: WeekTask)) -> Void)?
    @State private var tasksExpanded = true
    @State private var goalsExpanded = true
    @State private var plansExpanded = true
    @State private var searchText = ""
    @State private var isConfirmingDeleteAllTasks = false
    @State private var isConfirmingDeleteAllGoals = false
    @State private var isConfirmingDeleteAllPlans = false
    @State private var detailPlan: WeeklyPlan?
    @State private var detailGoal: WeeklyGoal?
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
                            TrashGoalCard(store: store, goal: goal) {
                                detailGoal = goal
                            }
                        }
                    }
                }

                ArchiveDisclosureSection(
                    title: "已删除周规划",
                    count: filteredDeletedPlans.count,
                    isExpanded: $plansExpanded,
                    trailingAction: {
                        if !filteredDeletedPlans.isEmpty {
                            deleteAllButton(
                                isConfirming: $isConfirmingDeleteAllPlans,
                                action: { store.permanentlyDeleteAllDeletedPlans() }
                            )
                        }
                    }
                ) {
                    if filteredDeletedPlans.isEmpty {
                        ArchiveEmptyRow(text: searchText.isEmpty ? "当前没有已删除周规划" : "没有匹配的规划")
                    } else {
                        ForEach(filteredDeletedPlans) { plan in
                            TrashPlanCard(store: store, plan: plan) {
                                detailPlan = plan
                            }
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
        .sheet(item: $detailPlan) { plan in
            PlanDetailView(store: store, plan: plan)
        }
        .sheet(item: $detailGoal) { goal in
            ArchivedGoalDetailView(goal: goal)
        }
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

    private var filteredDeletedPlans: [WeeklyPlan] {
        store.deletedPlans.filter { plan in
            matchesSearch(plan.title)
        }
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
    var onTap: (() -> Void)? = nil

    var body: some View {
        let completed = goal.subgoals.filter(\.isCompleted).count
        ArchiveItemCard(symbol: "trash") {
            WeekflowButton { onTap?() } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isConfirming = false }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isConfirming = true }
            }
        } label: {
            ZStack {
                Text("全部删除")
                    .opacity(isConfirming ? 0 : 1)
                    .scaleEffect(isConfirming ? 0.85 : 1)
                    .offset(x: isConfirming ? -8 : 0)
                Text("确认删除")
                    .opacity(isConfirming ? 1 : 0)
                    .scaleEffect(isConfirming ? 1 : 0.85)
                    .offset(x: isConfirming ? 0 : 8)
            }
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
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isConfirming)
    }

    private func cancelConfirmation() {
        guard isConfirming else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isConfirming = false }
    }
}

struct TrashPlanCard: View {
    @Bindable var store: WeekflowStore
    let plan: WeeklyPlan
    var onTap: (() -> Void)? = nil

    var body: some View {
        ArchiveItemCard(symbol: "trash") {
            WeekflowButton { onTap?() } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text("删除于 \((plan.archivedAt ?? .now).dayLabel)")
                        Text("·")
                        Text("\(store.goalsForPlan(plan.id).count) 个目标")
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
                restore: { store.restorePlan(id: plan.id) },
                destructive: { store.deletePlan(id: plan.id) }
            )
        }
    }
}
