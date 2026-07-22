import SwiftUI

enum WeekflowCornerRadius {
    /// Keep framed surfaces close to rectangular while preserving enough
    /// curvature to avoid visually harsh macOS controls.
    static func resolved(_ requestedRadius: CGFloat) -> CGFloat {
        guard requestedRadius > 0 else { return 0 }
        return max(1, (requestedRadius * 0.6).rounded())
    }
}

func WeekflowRoundedRectangle(
    cornerRadius: CGFloat,
    style: RoundedCornerStyle = .circular
) -> RoundedRectangle {
    RoundedRectangle(
        cornerRadius: WeekflowCornerRadius.resolved(cornerRadius),
        style: style
    )
}
