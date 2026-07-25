import SwiftUI

struct WeeklyReviewView: View {
    @Bindable var store: WeekflowStore
    private let usesScrollContainer: Bool
    private let referenceDate: Date

    init(
        store: WeekflowStore,
        usesScrollContainer: Bool = true,
        referenceDate: Date = .now
    ) {
        self.store = store
        self.usesScrollContainer = usesScrollContainer
        self.referenceDate = referenceDate
    }

    private var snapshot: WeeklyReviewSnapshot {
        WeeklyReviewSnapshot(
            goals: store.activeGoals,
            channels: store.channels,
            focusRecords: store.focusRecords,
            dailySummaries: store.dailySummaries,
            referenceDate: referenceDate
        )
    }

    var body: some View {
        Group {
            if usesScrollContainer {
                ScrollView {
                    reviewContent
                        .padding(.trailing, WeekflowLayout.scrollbarGutterWidth)
                }
            } else {
                reviewContent
            }
        }
        .background(WeekflowPalette.appBackground)
    }

    private var reviewContent: some View {
        let snapshot = snapshot
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("本周回顾").font(.largeTitle.weight(.bold))
                Text(Date.weekRangeLabel(for: referenceDate))
                    .foregroundStyle(WeekflowPalette.textSecondary)
            }

            WeeklyReviewOverviewCard(snapshot: snapshot)

            if !snapshot.goals.isEmpty {
                Text("本周任务目标完成情况")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .padding(.top, 4)
                ForEach(snapshot.goals) { goal in
                    WeeklyReviewGoalCard(goal: goal, store: store)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct WeeklyReviewOverviewCard: View {
    let snapshot: WeeklyReviewSnapshot
    @AppStorage(ChartPalettePreferences.storageKey)
    private var chartPaletteRawValue = ChartPalettePreferences.defaultPreset

    private var chartPalette: ChartPalettePreset {
        ChartPalettePreferences.preset(for: chartPaletteRawValue)
    }

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 110), spacing: 10),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本周数据")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WeekflowPalette.textPrimary)

            LazyVGrid(columns: columns, spacing: 10) {
                metric(
                    title: "目标完成率",
                    value: percentage(snapshot.goalCompletionRate),
                    detail: "\(snapshot.completedGoalCount) / \(snapshot.goals.count) 个目标"
                )
                metric(
                    title: "任务执行率",
                    value: percentage(snapshot.taskExecutionRate),
                    detail: "\(snapshot.performedTaskCount) / \(snapshot.taskEntries.count) 项已推进"
                )
                metric(
                    title: "计划时间",
                    value: snapshot.plannedMinutes.hourMinuteClockText,
                    detail: "本周任务计划"
                )
                metric(
                    title: "实际时间",
                    value: snapshot.actualMinutes.hourMinuteClockText,
                    detail: "任务累计计时"
                )
                metric(
                    title: "计划偏差",
                    value: varianceText,
                    detail: snapshot.varianceMinutes > 0 ? "超过计划" : "相对计划"
                )
                metric(
                    title: "专注时间",
                    value: snapshot.totalFocusMinutes.hourMinuteClockText,
                    detail: "禅定、学习与休闲"
                )
            }

            HStack(alignment: .top, spacing: 10) {
                WeeklyReviewRhythmChart(
                    metrics: snapshot.dayMetrics,
                    palette: chartPalette
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                WeeklyReviewTimeRing(
                    taskMinutes: snapshot.actualMinutes,
                    focusMinutes: snapshot.totalFocusMinutes,
                    palette: chartPalette
                )
                .frame(width: 230)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 176)

            WeeklyReviewBreakdown(snapshot: snapshot)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(WeekflowPalette.objective)
                Text(snapshot.summaryText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WeekflowPalette.objective.opacity(0.06), in: WeekflowRoundedRectangle(cornerRadius: 9))

        }
        .padding(16)
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 12))
        .overlay(WeekflowRoundedRectangle(cornerRadius: 12).stroke(WeekflowPalette.border))
    }

    private var varianceText: String {
        guard snapshot.varianceMinutes != 0 else { return "00:00" }
        let sign = snapshot.varianceMinutes > 0 ? "+" : "−"
        return sign + abs(snapshot.varianceMinutes).hourMinuteClockText
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func metric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(WeekflowPalette.textMuted)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(WeekflowPalette.textPrimary)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(WeekflowPalette.textSecondary)
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(WeekflowPalette.surfaceHover, in: WeekflowRoundedRectangle(cornerRadius: 9))
    }

}

struct WeeklyReviewRhythmChart: View {
    let metrics: [WeeklyReviewDayMetric]
    let palette: ChartPalettePreset
    @Environment(\.colorScheme) private var colorScheme

    private var maximumMinutes: CGFloat {
        CGFloat(max(metrics.map(\.totalMinutes).max() ?? 0, 1))
    }
    private var taskMinutes: Int { metrics.reduce(0) { $0 + $1.taskMinutes } }
    private var focusMinutes: Int { metrics.reduce(0) { $0 + $1.focusMinutes } }
    private var totalMinutes: Int { taskMinutes + focusMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本周节奏")
                .font(.system(size: 11, weight: .semibold))

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(metrics) { metric in
                    VStack(spacing: 5) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            if metric.focusMinutes > 0 {
                                Rectangle()
                                    .fill(WeekflowPalette.focusRing)
                                    .frame(height: segmentHeight(metric.focusMinutes))
                            }
                            if metric.taskMinutes > 0 {
                                Rectangle()
                                    .fill(palette.taskSummaryColor(for: colorScheme))
                                    .frame(height: segmentHeight(metric.taskMinutes))
                            }
                        }
                        .frame(width: 9, height: 76, alignment: .bottom)

                        Text(metric.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10))
                            .foregroundStyle(WeekflowPalette.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 14) {
                legend(
                    color: palette.taskSummaryColor(for: colorScheme),
                    title: "任务 \(shareText(taskMinutes))"
                )
                legend(
                    color: WeekflowPalette.focusRing,
                    title: "专注模式 \(shareText(focusMinutes))"
                )
            }
        }
        .padding(12)
        .background(WeekflowPalette.surfaceHover, in: WeekflowRoundedRectangle(cornerRadius: 9))
    }

    private func segmentHeight(_ minutes: Int) -> CGFloat {
        max(CGFloat(minutes) / maximumMinutes * 64, 2)
    }

    private func shareText(_ minutes: Int) -> String {
        guard totalMinutes > 0 else { return "0%" }
        return "\(Int((Double(minutes) / Double(totalMinutes) * 100).rounded()))%"
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 9.5)).foregroundStyle(WeekflowPalette.textMuted)
        }
    }
}

struct WeeklyReviewTimeRing: View {
    let taskMinutes: Int
    let focusMinutes: Int
    let palette: ChartPalettePreset
    @Environment(\.colorScheme) private var colorScheme

    private var total: Int { taskMinutes + focusMinutes }
    private var taskShare: Double { total == 0 ? 0 : Double(taskMinutes) / Double(total) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("投入结构")
                .font(.system(size: 11, weight: .semibold))

            ZStack {
                Circle().stroke(WeekflowPalette.border, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: taskShare)
                    .stroke(
                        palette.taskSummaryColor(for: colorScheme),
                        style: StrokeStyle(lineWidth: 7, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: taskShare, to: total == 0 ? taskShare : 1)
                    .stroke(WeekflowPalette.focusRing, style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Text(total.hourMinuteClockText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .frame(width: 82, height: 82)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                ringLegend("任务", taskMinutes, palette.taskSummaryColor(for: colorScheme))
                ringLegend("专注模式", focusMinutes, WeekflowPalette.focusRing)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        .background(WeekflowPalette.surfaceHover, in: WeekflowRoundedRectangle(cornerRadius: 9))
    }

    private func ringLegend(_ title: String, _ minutes: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10.5))
                Text(minutes.hourMinuteClockText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(WeekflowPalette.textMuted)
            }
        }
    }
}

struct WeeklyReviewBreakdown: View {
    let snapshot: WeeklyReviewSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            breakdownCard(title: "任务细分") {
                if snapshot.channelMetrics.isEmpty {
                    emptyState("本周还没有任务投入")
                } else {
                    ForEach(snapshot.channelMetrics) { metric in
                        taskChannelRow(metric)
                    }
                }
            }

            breakdownCard(title: "专注模式细分") {
                if snapshot.focusMetrics.isEmpty {
                    emptyState("本周还没有专注记录")
                } else {
                    ForEach(snapshot.focusMetrics) { metric in
                        focusModeRow(metric)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func breakdownCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .semibold))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WeekflowPalette.surfaceHover, in: WeekflowRoundedRectangle(cornerRadius: 9))
    }

    private func taskChannelRow(_ metric: WeeklyReviewChannelMetric) -> some View {
        HStack(spacing: 8) {
            Circle().fill(channelColor(metric.colorName)).frame(width: 7, height: 7)
            Text(metric.title).font(.system(size: 10.5, weight: .medium))
            Spacer()
            Text(metric.minutes.hourMinuteClockText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        }
        .padding(.vertical, 3)
    }

    private func focusModeRow(_ metric: WeeklyReviewFocusMetric) -> some View {
        HStack(spacing: 8) {
            Circle().fill(FocusModePreferences.color(for: metric.modeID)).frame(width: 7, height: 7)
            Text(FocusModePreferences.title(for: metric.modeID)).font(.system(size: 10.5, weight: .medium))
            Spacer()
            Text(metric.minutes.hourMinuteClockText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        }
        .padding(.vertical, 3)
    }

    private func emptyState(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5))
            .foregroundStyle(WeekflowPalette.textMuted)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    }

    private func channelColor(_ colorName: String) -> Color {
        TaskChannel(id: "review", title: "", colorName: colorName).color
    }
}

struct WeeklyReviewGoalCard: View {
    let goal: WeeklyGoal
    @Bindable var store: WeekflowStore
    @State private var showsSubgoals = true

    private var reviewTasks: [WeekTask] {
        goal.tasks.filter { !$0.isDeleted && ($0.status == .completed || !$0.isArchived) }
    }
    private var completedCount: Int { reviewTasks.filter { $0.status == .completed }.count }
    private var plannedMinutes: Int { reviewTasks.reduce(0) { $0 + $1.estimatedMinutes } }
    private var actualMinutes: Int { reviewTasks.reduce(0) { $0 + $1.actualMinutes } }
    private var statusTitle: String {
        if goal.carriedFromGoalID != nil { return "继续到下周" }
        if goal.progress >= 1 { return "已完成" }
        if goal.progress > 0 { return "部分完成" }
        return "未完成"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title)
                    .font(.system(size: 18, weight: .semibold))
                Text(statusTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(goal.progress >= 1 ? WeekflowPalette.complete : WeekflowPalette.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WeekflowPalette.surfaceSelected, in: Capsule())
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textSecondary)
            }

            WeekflowDailyProgressTrack(
                fraction: goal.progress,
                hasProgress: goal.progress > 0,
                alwaysVisible: true,
                accessibilityLabel: "周目标完成进度",
                accessibilityValue: "已完成 \(Int(goal.progress * 100))%"
            )
            .frame(height: 6)

            HStack(spacing: 18) {
                reviewValue("任务目标", "\(completedCount) / \(reviewTasks.count)")
                reviewValue("计划时间", plannedMinutes.hourMinuteClockText)
                reviewValue("实际时间", actualMinutes.hourMinuteClockText)
                Spacer()
                if !goal.subgoals.isEmpty {
                    WeekflowButton {
                        showsSubgoals.toggle()
                    } label: {
                        Label("\(goal.subgoals.count) 个子目标", systemImage: showsSubgoals ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .pointingHandCursor()
                }
            }

            if showsSubgoals {
                ForEach(goal.subgoals) { subgoal in
                    HStack(spacing: 8) {
                        Image(systemName: subgoal.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(subgoal.isCompleted ? WeekflowPalette.complete : WeekflowPalette.iconDefault)
                        Text(subgoal.title)
                            .font(.system(size: 12))
                            .strikethrough(subgoal.isCompleted)
                        Spacer()
                    }
                    .padding(.leading, 10)
                }
            }

            Divider()

            HStack(spacing: 10) {
                if goal.progress < 1 {
                    WeeklyReviewGoalAction(title: "继续到下周", symbol: "arrow.right", isPrimary: true) {
                        store.continueGoalToNextWeek(id: goal.id)
                    }
                }
                WeeklyReviewGoalAction(title: "归档", symbol: "archivebox") {
                    store.archiveGoal(id: goal.id)
                }
                Spacer()
            }
        }
        .padding(20)
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 12))
        .overlay(WeekflowRoundedRectangle(cornerRadius: 12).stroke(WeekflowPalette.border))
    }

    private func reviewValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(WeekflowPalette.textMuted)
        }
    }
}

struct WeeklyReviewGoalAction: View {
    let title: String
    let symbol: String
    var isPrimary = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isPrimary ? .white : WeekflowPalette.textSecondary)
                .frame(width: 96, height: 28)
                .background(
                    isPrimary
                        ? WeekflowPalette.objective.opacity(isHovering ? 0.84 : 1)
                        : (isHovering ? WeekflowPalette.surfaceSelected : WeekflowPalette.surfaceHover),
                    in: WeekflowRoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    if !isPrimary {
                        WeekflowRoundedRectangle(cornerRadius: 7)
                            .stroke(WeekflowPalette.border, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
    }
}
