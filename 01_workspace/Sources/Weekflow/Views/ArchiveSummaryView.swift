import SwiftUI

enum ArchiveChannelFilter {
    static func matches(channelID: String?, selectedChannelID: String) -> Bool {
        selectedChannelID == "all" || channelID == selectedChannelID
    }
}

struct ArchiveSummaryView: View {
    @Bindable var store: WeekflowStore
    let selectedChannelID: String
    let openTask: (((goal: WeeklyGoal, task: WeekTask)) -> Void)?
    let openGoal: ((WeeklyGoal) -> Void)?
    private let usesScrollContainer: Bool
    @State private var tasksExpanded = true
    @State private var goalsExpanded = true
    @State private var plansExpanded = true
    @State private var searchText = ""
    @State private var detailPlan: WeeklyPlan?
    @FocusState private var isSearchFocused: Bool

    init(
        store: WeekflowStore,
        selectedChannelID: String = "all",
        usesScrollContainer: Bool = true,
        openTask: (((goal: WeeklyGoal, task: WeekTask)) -> Void)? = nil,
        openGoal: ((WeeklyGoal) -> Void)? = nil
    ) {
        self.store = store
        self.selectedChannelID = selectedChannelID
        self.usesScrollContainer = usesScrollContainer
        self.openTask = openTask
        self.openGoal = openGoal
    }

    var body: some View {
        Group {
            if usesScrollContainer {
                ScrollView {
                    archiveContent.padding(.trailing, WeekflowLayout.scrollbarGutterWidth)
                }
            } else {
                archiveContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)
        .sheet(item: $detailPlan) { plan in
            PlanDetailView(store: store, plan: plan)
        }
    }

    private var archiveContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("已完成任务自动归档，也可手动归档。")
                .font(.system(size: 13))
                .foregroundStyle(WeekflowPalette.textSecondary)

            searchField

            ArchiveDisclosureSection(
                title: "已归档的任务",
                count: filteredTasks.count,
                isExpanded: $tasksExpanded
            ) {
                if filteredTasks.isEmpty {
                    ArchiveEmptyRow(text: searchText.isEmpty ? "当前筛选下没有归档任务" : "没有匹配的任务")
                } else {
                    ForEach(filteredTasks, id: \.task.id) { entry in
                        archivedTaskCard(entry)
                    }
                }
            }

            ArchiveDisclosureSection(
                title: "已归档的目标",
                count: filteredGoals.count,
                isExpanded: $goalsExpanded
            ) {
                if filteredGoals.isEmpty {
                    ArchiveEmptyRow(text: searchText.isEmpty ? "当前筛选下没有归档周目标" : "没有匹配的目标")
                } else {
                    ForEach(filteredGoals) { goal in archivedGoalCard(goal) }
                }
            }

            ArchiveDisclosureSection(
                title: "已归档周规划",
                count: filteredPlans.count,
                isExpanded: $plansExpanded
            ) {
                if filteredPlans.isEmpty {
                    ArchiveEmptyRow(text: searchText.isEmpty ? "当前没有归档周规划" : "没有匹配的规划")
                } else {
                    ForEach(filteredPlans) { plan in archivedPlanCard(plan) }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 1_040, alignment: .topLeading)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WeekflowPalette.textMuted)
            TextField("搜索已归档的内容…", text: $searchText)
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

    private var filteredTasks: [(goal: WeeklyGoal, task: WeekTask)] {
        store.archivedTasks.filter { entry in
            matchesChannel(entry.task.channelID) && matchesSearch(entry.task.title)
        }
    }

    private var filteredGoals: [WeeklyGoal] {
        store.archivedGoals.filter { goal in
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

    private var filteredPlans: [WeeklyPlan] {
        store.archivedPlans.filter { plan in
            matchesSearch(plan.title)
        }
    }

    private func archivedPlanCard(_ plan: WeeklyPlan) -> some View {
        ArchiveItemCard(symbol: "calendar.badge.checkmark") {
            WeekflowButton { detailPlan = plan } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text("归档于 \((plan.archivedAt ?? .now).dayLabel)")
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
                restore: { store.restorePlan(id: plan.id) },
                destructive: { store.deletePlan(id: plan.id) }
            )
        }
    }

    private func archivedTaskCard(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        ArchiveItemCard(symbol: "archivebox") {
            WeekflowButton { openTask?(entry) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text("归档于 \((entry.task.archivedAt ?? entry.task.updatedAt).dayLabel)")
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
                restore: {
                store.restoreTask(goalID: entry.goal.id, taskID: entry.task.id)
                },
                destructive: {
                store.deleteTask(goalID: entry.goal.id, taskID: entry.task.id)
                }
            )
        }
    }

    private func archivedGoalCard(_ goal: WeeklyGoal) -> some View {
        let completed = goal.subgoals.filter(\.isCompleted).count
        return ArchiveItemCard(symbol: "archivebox") {
            WeekflowButton { openGoal?(goal) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(goal.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textPrimary)
                        .lineLimit(1)
                    Text("归档于 \((goal.archivedAt ?? .now).dayLabel) · \(completed) 个子目标已完成")
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
                restore: {
                store.restoreGoal(id: goal.id)
                },
                destructive: {
                store.deleteGoal(id: goal.id)
                }
            )
        }
    }
}

struct ArchiveDisclosureSection<Content: View, Trailing: View>: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    @ViewBuilder let trailingAction: () -> Trailing
    @ViewBuilder let content: Content

    init(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailingAction: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self._isExpanded = isExpanded
        self.trailingAction = trailingAction
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            WeekflowButton { withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() } } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundStyle(WeekflowPalette.textMuted)
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(WeekflowPalette.border.opacity(0.35), in: Capsule())
                    Spacer()
                    trailingAction()
                }
                .foregroundStyle(WeekflowPalette.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 9) { content }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(WeekflowPalette.surface.opacity(0.45), in: WeekflowRoundedRectangle(cornerRadius: 12))
        .overlay(WeekflowRoundedRectangle(cornerRadius: 12).stroke(WeekflowPalette.border.opacity(0.7)))
        .clipped()
    }
}

struct ArchiveItemCard<Label: View, Actions: View>: View {
    let symbol: String
    @ViewBuilder let label: Label
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WeekflowPalette.textMuted)
                .frame(width: 18, height: 24)
            label
            HStack(spacing: 7) { actions }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 62)
        .background(WeekflowPalette.surface.opacity(0.78), in: WeekflowRoundedRectangle(cornerRadius: 9))
        .overlay(WeekflowRoundedRectangle(cornerRadius: 9).stroke(WeekflowPalette.border.opacity(0.62)))
    }
}

struct ArchiveCapsuleActions: View {
    let destructiveTitle: String
    var requiresDestructiveConfirmation = false
    let restore: () -> Void
    let destructive: () -> Void
    @State private var isConfirmingDestructive = false
    @State private var hoveredAction: Action?

    private enum Action: Equatable {
        case restore
        case destructive
    }

    var body: some View {
        HStack(spacing: 0) {
            capsuleButton(
                title: "恢复",
                symbol: "arrow.counterclockwise",
                action: .restore,
                color: WeekflowPalette.textSecondary,
                width: 76,
                handler: restore
            )

            Rectangle()
                .fill(WeekflowPalette.border.opacity(0.7))
                .frame(width: 1, height: 18)

            WeekflowButton(action: destructiveTapped) {
                ZStack {
                    Label(destructiveTitle, systemImage: "trash")
                        .opacity(isConfirmingDestructive ? 0 : 1)
                        .offset(x: isConfirmingDestructive ? -12 : 0)
                    Label("彻底删除", systemImage: "trash.fill")
                        .opacity(isConfirmingDestructive ? 1 : 0)
                        .offset(x: isConfirmingDestructive ? 0 : 12)
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(
                    isConfirmingDestructive
                        ? WeekflowPalette.danger
                        : WeekflowPalette.textSecondary
                )
                .frame(width: 82, height: 30)
                .background(
                    isConfirmingDestructive
                        ? WeekflowPalette.danger.opacity(0.1)
                        : (hoveredAction == .destructive ? WeekflowPalette.surfaceHover : .clear),
                    in: Capsule()
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hoveredAction = $0 ? .destructive : nil }
        }
        .padding(3)
        .background(WeekflowPalette.surface.opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(WeekflowPalette.border.opacity(0.78), lineWidth: 1))
        .background {
            if isConfirmingDestructive {
                GeometryReader { proxy in
                    WindowOutsideClickMonitor(
                        protectedRect: CGRect(origin: .zero, size: proxy.size),
                        monitoredEventMask: .leftMouseDown,
                        action: cancelDestructiveConfirmation
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isConfirmingDestructive)
    }

    private func capsuleButton(
        title: String,
        symbol: String,
        action: Action,
        color: Color,
        width: CGFloat,
        handler: @escaping () -> Void
    ) -> some View {
        WeekflowButton(action: handler) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(color)
                .frame(width: width, height: 30)
                .background(
                    hoveredAction == action ? WeekflowPalette.surfaceHover : .clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hoveredAction = $0 ? action : nil }
    }

    private func destructiveTapped() {
        guard requiresDestructiveConfirmation else {
            destructive()
            return
        }
        if isConfirmingDestructive {
            destructive()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isConfirmingDestructive = true
            }
        }
    }

    private func cancelDestructiveConfirmation() {
        guard isConfirmingDestructive else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            isConfirmingDestructive = false
        }
    }
}

struct ArchiveEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(WeekflowPalette.textMuted)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
    }
}

/// Detail view for an archived/deleted plan showing its goals and subgoals.
struct PlanDetailView: View {
    @Bindable var store: WeekflowStore
    let plan: WeeklyPlan
    @Environment(\.dismiss) private var dismiss

    private var planGoals: [WeeklyGoal] {
        store.goals.filter { $0.planID == plan.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(plan.startDate.formatted(.dateTime.month().day())) – \(plan.endDate.formatted(.dateTime.month().day()))")
                        .font(.system(size: 12))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
                Spacer()
                WeekflowButton { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .padding(20)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(planGoals.count) 个周目标")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textSecondary)

                    if planGoals.isEmpty {
                        Text("该规划下没有目标")
                            .font(.system(size: 12))
                            .foregroundStyle(WeekflowPalette.textMuted)
                    } else {
                        ForEach(planGoals) { goal in
                            planGoalRow(goal)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 480)
        .background(WeekflowPalette.surface)
    }

    private func planGoalRow(_ goal: WeeklyGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WeekflowPalette.objective)
                Text(goal.title.isEmpty ? "未命名目标" : goal.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                Spacer()
                if !goal.outcome.isEmpty {
                    Text(goal.outcome)
                        .font(.system(size: 11))
                        .foregroundStyle(WeekflowPalette.textMuted)
                        .lineLimit(1)
                }
            }
            if !goal.subgoals.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(goal.subgoals) { subgoal in
                        HStack(spacing: 6) {
                            Image(systemName: subgoal.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10))
                                .foregroundStyle(subgoal.isCompleted ? WeekflowPalette.objective : WeekflowPalette.textMuted)
                            Text(subgoal.title)
                                .font(.system(size: 12))
                                .foregroundStyle(WeekflowPalette.textSecondary)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
        .padding(12)
        .background(WeekflowPalette.surfaceHover.opacity(0.5), in: WeekflowRoundedRectangle(cornerRadius: 8))
        .overlay(
            WeekflowRoundedRectangle(cornerRadius: 8)
                .stroke(WeekflowPalette.border.opacity(0.5))
        )
    }
}

/// Detail view for a single archived goal showing its subgoals.
struct ArchivedGoalDetailView: View {
    let goal: WeeklyGoal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title.isEmpty ? "未命名目标" : goal.title)
                        .font(.system(size: 17, weight: .semibold))
                    if !goal.outcome.isEmpty {
                        Text(goal.outcome)
                            .font(.system(size: 12))
                            .foregroundStyle(WeekflowPalette.textMuted)
                    }
                }
                Spacer()
                WeekflowButton { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .padding(20)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let completed = goal.subgoals.filter(\.isCompleted).count
                    Text("\(goal.subgoals.count) 个子目标，\(completed) 个已完成")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textSecondary)

                    if goal.subgoals.isEmpty {
                        Text("没有子目标")
                            .font(.system(size: 12))
                            .foregroundStyle(WeekflowPalette.textMuted)
                    } else {
                        ForEach(goal.subgoals) { subgoal in
                            HStack(spacing: 8) {
                                Image(systemName: subgoal.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(subgoal.isCompleted ? WeekflowPalette.objective : WeekflowPalette.textMuted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(subgoal.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(WeekflowPalette.textPrimary)
                                    if !subgoal.detail.isEmpty {
                                        Text(subgoal.detail)
                                            .font(.system(size: 11))
                                            .foregroundStyle(WeekflowPalette.textMuted)
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WeekflowPalette.surfaceHover.opacity(0.5), in: WeekflowRoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 380, height: 420)
        .background(WeekflowPalette.surface)
    }
}
