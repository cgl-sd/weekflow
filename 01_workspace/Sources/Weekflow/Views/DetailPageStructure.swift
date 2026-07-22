import SwiftUI

struct DetailPageStructure<PropertyBar: View, Content: View>: View {
    private let propertyBar: PropertyBar
    private let content: Content

    init(
        @ViewBuilder propertyBar: () -> PropertyBar,
        @ViewBuilder content: () -> Content
    ) {
        self.propertyBar = propertyBar()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            propertyBar
            content
        }
        .frame(
            width: WeekflowLayout.taskDetailSheetWidth,
            height: WeekflowLayout.taskDetailSheetHeight,
            alignment: .topLeading
        )
        .background(WeekflowPalette.surface)
    }
}

struct DetailPagePropertyBar<Leading: View, Values: View, Actions: View>: View {
    private let leading: Leading
    private let values: Values
    private let actions: Actions

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder values: () -> Values,
        @ViewBuilder actions: () -> Actions
    ) {
        self.leading = leading()
        self.values = values()
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leading
                .frame(minWidth: 118, alignment: .leading)
            Spacer(minLength: 24)
            values
                .fixedSize(horizontal: true, vertical: false)
            actions
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .foregroundStyle(WeekflowPalette.secondaryText)
    }
}

private struct DetailPageContentLayout: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 42)
            .padding(.top, 40)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension View {
    func detailPageContentLayout() -> some View {
        modifier(DetailPageContentLayout())
    }
}
