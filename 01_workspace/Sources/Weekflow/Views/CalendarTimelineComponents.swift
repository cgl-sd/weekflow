import SwiftUI

/// A full-width end-of-day marker used instead of an ordinary event card.
/// The wave-line-wave treatment remains visible across the complete day lane.
struct CalendarCutoffFence: View {
    var color: Color = .purple

    var body: some View {
        VStack(spacing: 1) {
            CalendarWaveLine()
                .stroke(color.opacity(0.72), lineWidth: 1)
            Rectangle()
                .fill(color.opacity(0.88))
                .frame(height: 1)
            CalendarWaveLine()
                .stroke(color.opacity(0.72), lineWidth: 1)
        }
        .frame(height: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("工作截止时间")
    }
}

private struct CalendarWaveLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let middleY = rect.midY
        let wavelength: CGFloat = 8
        path.move(to: CGPoint(x: rect.minX, y: middleY))

        var x = rect.minX
        while x < rect.maxX {
            let endX = min(x + wavelength, rect.maxX)
            let midpointX = min(x + wavelength / 2, rect.maxX)
            path.addQuadCurve(
                to: CGPoint(x: midpointX, y: middleY),
                control: CGPoint(x: x + wavelength / 4, y: rect.minY)
            )
            path.addQuadCurve(
                to: CGPoint(x: endX, y: middleY),
                control: CGPoint(x: x + wavelength * 3 / 4, y: rect.maxY)
            )
            x += wavelength
        }
        return path
    }
}
