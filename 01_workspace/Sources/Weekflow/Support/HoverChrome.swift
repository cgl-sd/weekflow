import SwiftUI

private struct BoxHoverChromeModifier: ViewModifier {
    let isHovering: Bool
    let cornerRadius: CGFloat
    let fill: Color
    let border: Color
    let hoverBorder: Color
    let hoverShadowOpacity: Double
    let hoverShadowRadius: CGFloat
    let hoverShadowY: CGFloat

    func body(content: Content) -> some View {
        let shape = WeekflowRoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(fill)
                    .shadow(
                        color: .black.opacity(isHovering ? hoverShadowOpacity : 0),
                        radius: isHovering ? hoverShadowRadius : 0,
                        y: isHovering ? hoverShadowY : 0
                    )
            }
            .overlay {
                shape
                    .strokeBorder(
                        isHovering ? hoverBorder : border,
                        lineWidth: 1,
                        antialiased: true
                    )
            }
    }
}

extension View {
    /// Shared hover treatment for framed controls: preserve the surface while
    /// strengthening the outline and elevation instead of filling the control.
    func boxHoverChrome(
        isHovering: Bool,
        cornerRadius: CGFloat,
        fill: Color = WeekflowPalette.surface,
        border: Color = WeekflowPalette.border.opacity(0.55),
        hoverBorder: Color = WeekflowPalette.border,
        hoverShadowOpacity: Double = 0.10,
        hoverShadowRadius: CGFloat = 1.5,
        hoverShadowY: CGFloat = 3
    ) -> some View {
        modifier(
            BoxHoverChromeModifier(
                isHovering: isHovering,
                cornerRadius: cornerRadius,
                fill: fill,
                border: border,
                hoverBorder: hoverBorder,
                hoverShadowOpacity: hoverShadowOpacity,
                hoverShadowRadius: hoverShadowRadius,
                hoverShadowY: hoverShadowY
            )
        )
    }
}
