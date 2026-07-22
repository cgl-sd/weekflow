import SwiftUI

enum TaskCardPresentationAnchor: Hashable {
    case card(UUID)
    case dateButton(UUID)
    case channelButton(UUID)
    case priorityButton(UUID)
    case timerButton(UUID)
    case timerDivider(UUID)
    case startTimeButton(UUID)
    case durationButton(UUID)
    case estimatedDurationButton(UUID)
}

struct TaskDurationMenuAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [TaskCardPresentationAnchor: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TaskCardPresentationAnchor: Anchor<CGRect>],
        nextValue: () -> [TaskCardPresentationAnchor: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct TaskDurationMenuPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Draws only the two exposed sides so the pointer and menu surface read as
/// one continuous speech-bubble outline.
struct TaskDurationMenuPointerOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
