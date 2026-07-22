import SwiftUI

struct WeekDayColumn: View {
    let date: Date
    let entries: [(goal: WeeklyGoal, task: WeekTask)]
    @Bindable var store: WeekflowStore
    @Binding var draggedTaskToken: TaskDragToken?
    @State private var isDropTarget = false
    @State private var taskRowFrames: [UUID: CGRect] = [:]

    private var dragCoordinateSpace: String {
        "weekly-day-drop-\(SystemBusinessCalendar.current.day(containing: date).persistenceKey)"
    }

    init(
        date: Date,
        entries: [(goal: WeeklyGoal, task: WeekTask)],
        store: WeekflowStore,
        draggedTaskToken: Binding<TaskDragToken?> = .constant(nil)
    ) {
        self.date = date
        self.entries = entries
        self.store = store
        _draggedTaskToken = draggedTaskToken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.headline)
                    Text(date.formatted(.dateTime.month().day())).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entries.count) 项")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Divider()
            ForEach(entries, id: \.task.id) { entry in
                WeeklyAssignedTaskCard(
                    entry: entry,
                    date: date,
                    tint: store.channel(for: entry.task.channelID)?.color ?? WeekflowPalette.iconDefault,
                    channelTitle: store.channel(for: entry.task.channelID)?.title,
                    dragStarted: { draggedTaskToken = $0 },
                    remove: {
                        if entry.task.isAssigned(on: date) {
                            store.removeTaskAssignment(goalID: entry.goal.id, taskID: entry.task.id, from: date)
                        } else {
                            store.moveTask(goalID: entry.goal.id, taskID: entry.task.id, to: nil)
                        }
                    }
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: WeeklyTaskRowFramePreferenceKey.self,
                            value: [
                                entry.task.id: proxy.frame(in: .named(dragCoordinateSpace))
                            ]
                        )
                    }
                }
            }
            Spacer(minLength: 70)
        }
        .padding(12)
        .frame(width: 190, alignment: .topLeading)
        .frame(minHeight: 230, alignment: .topLeading)
        .background(
            isDropTarget ? WeekflowPalette.surfaceSelected : WeekflowPalette.surfaceHover,
            in: WeekflowRoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            WeekflowRoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDropTarget ? WeekflowPalette.borderStrong : WeekflowPalette.border,
                    style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: isDropTarget ? [6, 4] : [])
                )
        )
        .overlay {
            if isDropTarget {
                VStack {
                    Spacer()
                    Label("放到这里", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
        .contentShape(Rectangle())
        .coordinateSpace(name: dragCoordinateSpace)
        .onPreferenceChange(WeeklyTaskRowFramePreferenceKey.self) {
            taskRowFrames = $0
        }
        .onDrop(
            of: [.utf8PlainText],
            delegate: HomeColumnTaskDropDelegate(
                draggedTaskToken: $draggedTaskToken,
                date: date,
                rowFrames: { taskRowFrames },
                store: store,
                isDropTarget: $isDropTarget
            )
        )
        .animation(.easeOut(duration: 0.14), value: isDropTarget)
    }
}

struct WeeklyTaskRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct WeeklyAssignedTaskCard: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    let date: Date
    let tint: Color
    let channelTitle: String?
    let dragStarted: (TaskDragToken) -> Void
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 7) {
                Circle()
                    .fill(entry.task.status == .completed ? WeekflowPalette.complete : tint)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                Text(entry.task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isHovering {
                    WeekflowButton(action: remove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .foregroundStyle(WeekflowPalette.iconDefault)
                    .help("移除这一天的分配")
                }
            }

            Text(entry.goal.title)
                .font(.system(size: 9.5))
                .foregroundStyle(WeekflowPalette.textMuted)
                .lineLimit(1)

            HStack {
                Label(entry.task.estimatedMinutes.hourMinuteClockText, systemImage: "clock")
                Spacer()
                if let channel = channelTitle {
                    Label(channel, systemImage: "number")
                }
            }
            .font(.system(size: 9.5))
            .foregroundStyle(tint)
        }
        .padding(7)
        .frame(
            maxWidth: .infinity,
            minHeight: WeekflowLayout.weeklyAssignedTaskCardMinimumHeight,
            alignment: .topLeading
        )
        .boxHoverChrome(
            isHovering: isHovering,
            cornerRadius: 8,
            fill: entry.task.status == .completed
                ? WeekflowPalette.complete.opacity(0.09)
                : tint.opacity(0.08),
            border: tint.opacity(0.25),
            hoverBorder: tint.opacity(0.55)
        )
        .contentShape(WeekflowRoundedRectangle(cornerRadius: 8))
        .pointingHandCursor()
        .onDrag {
            let token = TaskDragToken(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                sourceDate: date
            )
            dragStarted(token)
            return NSItemProvider(object: token.value as NSString)
        } preview: {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(entry.goal.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(WeekflowPalette.textMuted)
                    .lineLimit(1)
            }
            .padding(7)
            .frame(
                width: 166,
                height: WeekflowLayout.weeklyAssignedTaskCardMinimumHeight,
                alignment: .topLeading
            )
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.45), lineWidth: 1)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
            case .ended:
                isHovering = false
            }
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

}

/// A simple wrapping layout makes the weekly task pool work at different window widths.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 500
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            x += size.width + spacing; lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += lineHeight + spacing; lineHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; lineHeight = max(lineHeight, size.height)
        }
    }
}
