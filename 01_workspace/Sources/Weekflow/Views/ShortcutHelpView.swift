import SwiftUI

struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        ("?", "打开快捷键说明"),
        ("A", "新建任务"),
        ("Enter / ⌘ Enter", "打开高亮任务 / 保存后打开详情"),
        ("Space", "开始或暂停当前任务"),
        ("C", "切换完成状态"),
        ("F", "进入专注模式"),
        ("X", "自动安排到当天日历"),
        ("D", "推迟一天"),
        ("Z", "移入待办箱"),
        ("⌘ Delete", "删除高亮任务")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快捷键").font(.title2.weight(.bold))
            ForEach(shortcuts, id: \.0) { item in
                HStack {
                    Text(item.0).font(.system(.body)).padding(.horizontal, 7).padding(.vertical, 3).background(WeekflowPalette.button, in: WeekflowRoundedRectangle(cornerRadius: 5))
                    Text(item.1)
                    Spacer()
                }
            }
            Spacer()
            HStack { Spacer(); WeekflowButton("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 390, height: 420, alignment: .topLeading)
    }
}
