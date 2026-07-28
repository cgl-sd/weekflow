import SwiftUI

struct DailyShutdownView: View {
    @Bindable var store: WeekflowStore
    let referenceDate: Date
    @State private var phase = 0
    @State private var originalTaskIDs: Set<UUID> = []
    @State private var summary = ""
    @State private var hasLoadedSummary = false
    @State private var summarySaveTask: Task<Void, Never>?

    init(store: WeekflowStore, initialPhase: Int = 0, referenceDate: Date = .now) {
        self.store = store
        self.referenceDate = referenceDate
        _phase = State(initialValue: initialPhase)
    }

    private var reviewEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        if originalTaskIDs.isEmpty { return shutdownSourceEntries }
        return store.activeTasks.filter { originalTaskIDs.contains($0.task.id) }
    }

    private var shutdownSourceEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        var seenTaskIDs = Set<UUID>()
        return (store.tasks(on: referenceDate) + store.completionCreditTasks(on: referenceDate)).filter {
            seenTaskIDs.insert($0.task.id).inserted
        }
    }

    var body: some View {
        Group {
            if phase == 0 {
                GeometryReader { proxy in
                    let columnWidth = WeekflowLayout.threeColumnWidth(
                        for: proxy.size.width,
                        columnSpacing: WeekflowLayout.dailyWorkspaceColumnSpacing
                    )
                    HStack(alignment: .top, spacing: WeekflowLayout.dailyWorkspaceColumnSpacing) {
                        reviewSummaryColumn
                            .frame(width: columnWidth)
                        reviewedTaskColumn(
                            title: "已完成",
                            entries: completedEntries,
                            emptyText: "今天还没有完成任务"
                        )
                        .frame(width: columnWidth)
                        reviewedTaskColumn(
                            title: "未完成",
                            entries: unfinishedEntries,
                            emptyText: "今天没有未完成任务"
                        )
                        .frame(width: columnWidth)
                    }
                }
            } else {
                summaryEditor
            }
        }
        .onAppear {
            if originalTaskIDs.isEmpty {
                originalTaskIDs = Set(shutdownSourceEntries.map { $0.task.id })
            }
            loadOrPrepareSummaryIfNeeded()
        }
        .onDisappear {
            summarySaveTask?.cancel()
            if hasLoadedSummary { store.saveDailySummary(summary, on: referenceDate) }
        }
        .background(WeekflowPalette.canvas)
    }

    private var progressedEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        reviewEntries.filter { $0.task.hasExecutionProgress }
    }

    private var notStartedEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        reviewEntries.filter { !$0.task.hasExecutionProgress }
    }

    private var completedEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        reviewEntries.filter { $0.task.status == .completed }
    }

    private var unfinishedEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        reviewEntries.filter { $0.task.status != .completed }
    }

    private var reviewSummaryColumn: some View {
        PlanningInstructionColumn(
            title: "今日回顾",
            detail: "看看今天已经推进了什么，还有哪些事项尚未开始。",
            backTitle: nil,
            nextTitle: "下一步",
            back: nil,
            next: {
                prepareSummary()
                phase = 1
            }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ShutdownTimeMetric(
                        title: "用时",
                        minutes: reviewEntries.reduce(0) {
                            $0 + DailyShutdownTimeDistribution.reviewMinutes(for: $1.task)
                        },
                        tint: WeekflowPalette.objective
                    )
                    ShutdownTimeMetric(
                        title: "计划",
                        minutes: reviewEntries.reduce(0) { $0 + $1.task.estimatedMinutes },
                        tint: WeekflowPalette.secondaryText
                    )
                }

                Text("时间花在哪里")
                    .font(.system(size: 14, weight: .semibold))
                ChannelTimeDonut(entries: reviewEntries, store: store)
                    .frame(height: 236)
            }
        }
    }

    private func reviewedTaskColumn(
        title: String,
        entries: [(goal: WeeklyGoal, task: WeekTask)],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: WeekflowLayout.dailyWorkspaceContentSpacing) {
            DailyWorkspaceColumnHeader(
                title: title,
                detail: "今日任务",
                badge: "\(entries.count)"
            ) {
                EmptyView()
            }
            ShutdownTaskGroupColumn(
                entries: entries,
                emptyText: emptyText,
                store: store,
                referenceDate: referenceDate
            )
        }
        .padding(.top, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.bottom, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.horizontal, WeekflowLayout.dailyWorkspaceColumnHorizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summaryEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PlanningNavigationButton(
                    title: "返回",
                    role: .secondary,
                    action: { phase = 0 }
                )
                .frame(width: 88)
                Spacer()
                Text("今日总结")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Color.clear.frame(width: 88, height: WeekflowLayout.primaryActionHeight)
            }
            TextEditor(text: Binding(
                get: { summary },
                set: { newValue in
                    summary = newValue
                    scheduleSummarySave()
                }
            ))
            .font(.system(size: 14))
            .padding(14)
            .background(WeekflowPalette.button, in: WeekflowRoundedRectangle(cornerRadius: 10))
            .overlay(WeekflowRoundedRectangle(cornerRadius: 10).stroke(WeekflowPalette.border, lineWidth: 1))
        }
        .padding(36)
    }

    private func prepareSummary() {
        if let saved = store.dailySummary(on: referenceDate), !saved.content.isEmpty {
            summary = saved.content
        } else {
            summary = summaryTemplate(reviewEntries)
            store.saveDailySummary(summary, on: referenceDate)
        }
        hasLoadedSummary = true
    }

    private func scheduleSummarySave() {
        summarySaveTask?.cancel()
        let content = summary
        summarySaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            store.saveDailySummary(content, on: referenceDate)
        }
    }

    private func loadOrPrepareSummaryIfNeeded() {
        guard !hasLoadedSummary else { return }
        if let saved = store.dailySummary(on: referenceDate) {
            summary = saved.content
            hasLoadedSummary = true
        } else if phase > 0 {
            prepareSummary()
        }
    }

    private func summaryTemplate(_ entries: [(goal: WeeklyGoal, task: WeekTask)]) -> String {
        DailyShutdownSummaryBuilder.build(
            entries: entries,
            focusMinutes: store.focusMinutes(on: referenceDate),
            channelTitle: { store.channel(for: $0)?.title ?? "未分类" }
        )
    }
}

struct ShutdownTaskGroupColumn: View {
    let entries: [(goal: WeeklyGoal, task: WeekTask)]
    let emptyText: String
    @Bindable var store: WeekflowStore
    let referenceDate: Date

    var body: some View {
        GeometryReader { proxy in
            let taskScrollViewportWidth = WeekflowLayout.homeTaskScrollViewportWidth(
                for: proxy.size.width
            )
            let showsVerticalScroller = WeekflowLayout.homeShowsVerticalScroller(
                taskCount: entries.count,
                expandedAdditionalHeight: 0,
                viewportHeight: proxy.size.height
            )
            let taskCardWidth = WeekflowLayout.homeTaskCardWidth(
                for: proxy.size.width,
                showsVerticalScroller: showsVerticalScroller
            )

            ScrollView(.vertical) {
                LazyVStack(spacing: WeekflowLayout.homeTaskCardSpacing) {
                    ForEach(entries, id: \.task.id) { entry in
                        let rolloverAction = rolloverAction(for: entry)
                        SunsamaTaskCard(
                            entry: entry,
                            store: store,
                            dragSourceDate: referenceDate,
                            compactHeight: WeekflowLayout.homeTaskCardHeight,
                            showsDateControl: false,
                            showsEstimatedDurationMenu: .constant(false),
                            showsStartTimeMenu: .constant(false),
                            showsDateMenu: .constant(false),
                            showsChannelMenu: .constant(false),
                            showsPriorityMenu: .constant(false),
                            auxiliaryActionSymbol: rolloverAction == nil ? nil : "arrow.right",
                            auxiliaryActionHelp: "移到明天",
                            auxiliaryAction: rolloverAction
                        )
                    }
                    if entries.isEmpty {
                        Text(emptyText)
                            .font(.system(size: 11))
                            .foregroundStyle(WeekflowPalette.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                }
                .frame(width: taskCardWidth, alignment: .topLeading)
                .frame(minHeight: 70, alignment: .topLeading)
                .background(
                    ZeroInsetVerticalScroller(
                        isVisible: showsVerticalScroller,
                        columnWidth: taskScrollViewportWidth,
                        scrollRequest: nil,
                        onTrackWidthChange: { _ in }
                    )
                )
            }
            .frame(
                width: taskScrollViewportWidth,
                height: proxy.size.height,
                alignment: .topLeading
            )
            .scrollIndicators(.visible)
        }
    }

    private func rolloverAction(
        for entry: (goal: WeeklyGoal, task: WeekTask)
    ) -> (() -> Void)? {
        guard entry.task.status != .completed,
              !isScheduled(entry.task, on: tomorrow) else { return nil }
        return {
            store.rolloverTaskManually(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                from: referenceDate,
                to: tomorrow
            )
        }
    }

    private var tomorrow: Date {
        SystemBusinessCalendar.current.calendar.date(
            byAdding: .day,
            value: 1,
            to: SystemBusinessCalendar.current.calendar.startOfDay(for: referenceDate)
        ) ?? referenceDate
    }

    private func isScheduled(_ task: WeekTask, on date: Date) -> Bool {
        let calendar = SystemBusinessCalendar.current.calendar
        return task.plannedDate.map {
            calendar.isDate($0, inSameDayAs: date)
        } == true || task.isAssigned(on: date, calendar: calendar)
    }
}

struct PlanningInstructionColumn<Supplement: View>: View {
    let title: String
    let detail: String
    let backTitle: String?
    let nextTitle: String
    let back: (() -> Void)?
    let next: () -> Void
    @ViewBuilder let supplement: () -> Supplement

    var body: some View {
        VStack(alignment: .leading, spacing: WeekflowLayout.dailyWorkspaceContentSpacing) {
            DailyWorkspaceColumnHeader(title: title, detail: detail, badge: nil) {
                EmptyView()
            }
            supplement()
            Spacer()
            HStack(spacing: 8) {
                if let backTitle, let back {
                    PlanningNavigationButton(
                        title: backTitle,
                        role: .secondary,
                        action: back
                    )
                    .frame(maxWidth: .infinity)
                }
                PlanningNavigationButton(
                    title: nextTitle,
                    role: .primary,
                    action: next
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.bottom, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.horizontal, WeekflowLayout.dailyWorkspaceColumnHorizontalInset)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

struct DailyWorkspaceColumnHeader<Trailing: View>: View {
    let title: String
    let detail: String
    let badge: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
                Spacer(minLength: 6)
                trailing()
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: WeekflowLayout.dailyWorkspaceHeaderHeight,
            maxHeight: WeekflowLayout.dailyWorkspaceHeaderHeight,
            alignment: .topLeading
        )
    }
}

struct PlanningNavigationButton: View {
    enum Role {
        case primary
        case secondary
    }

    let title: String
    let role: Role
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(role == .primary ? .white : WeekflowPalette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: WeekflowLayout.primaryActionHeight)
                .background(background, in: WeekflowRoundedRectangle(cornerRadius: 8))
                .overlay(
                    WeekflowRoundedRectangle(cornerRadius: 8)
                        .stroke(role == .secondary ? border : .clear)
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .contentShape(WeekflowRoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var background: Color {
        switch role {
        case .primary:
            isHovering ? WeekflowPalette.objective.opacity(0.86) : WeekflowPalette.objective
        case .secondary:
            isHovering ? WeekflowPalette.surfaceSelected : WeekflowPalette.surfaceHover
        }
    }

    private var border: Color {
        isHovering ? WeekflowPalette.borderStrong : WeekflowPalette.border
    }
}

struct PlanningDropRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct PlanningSortMenuAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
