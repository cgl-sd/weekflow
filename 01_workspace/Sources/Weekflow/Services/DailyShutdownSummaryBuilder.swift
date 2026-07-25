import Foundation

struct DailyShutdownSummaryBuilder {
    static func build(
        entries: [(goal: WeeklyGoal, task: WeekTask)],
        focusMinutes: [String: Int],
        channelTitle: (String?) -> String
    ) -> String {
        let progressed = entries.filter { $0.task.hasExecutionProgress }
        let notStarted = entries.filter { !$0.task.hasExecutionProgress }

        let progressedLines = progressed.map { entry in
            let result: String
            if entry.task.status == .completed {
                result = "已完成"
            } else if entry.task.subtasks.contains(where: \.completed) {
                let count = entry.task.subtasks.filter(\.completed).count
                result = "已推进 \(count)/\(entry.task.subtasks.count) 个子任务"
            } else {
                result = "进行中"
            }
            return "- \(entry.task.title)｜实际时间 \(entry.task.actualMinutes.hourMinuteClockText)｜结果：\(result)"
        }.joined(separator: "\n")

        let notStartedLines = notStarted
            .map { "- \($0.task.title)" }
            .joined(separator: "\n")

        let focusLines = FocusModePreferences.modes.map { mode in
            "- \(mode.title)：\((focusMinutes[mode.id] ?? 0).hourMinuteClockText)"
        }.joined(separator: "\n")
        let totalFocusMinutes = FocusModePreferences.modes.reduce(0) { $0 + (focusMinutes[$1.id] ?? 0) }

        let channelLines = Dictionary(grouping: entries) { $0.task.channelID }
            .compactMap { channelID, tasks -> (String, Int)? in
                let minutes = tasks.reduce(0) { $0 + $1.task.actualMinutes }
                guard minutes > 0 else { return nil }
                return (channelTitle(channelID), minutes)
            }
            .sorted { $0.0 < $1.0 }
            .map { "- \($0.0)：\($0.1.hourMinuteClockText)" }
            .joined(separator: "\n")

        return """
        ## 今日已经进行的事项
        \(progressedLines.isEmpty ? "- 无" : progressedLines)

        ## 今日尚未实施的事项
        \(notStartedLines.isEmpty ? "- 无" : notStartedLines)

        ## 今日专注情况
        \(focusLines)
        - 总专注时长：\(totalFocusMinutes.hourMinuteClockText)

        ## 时间分布
        \(channelLines.isEmpty ? "- 暂无实际计时" : channelLines)

        ## 今日总结


        ## 明日注意事项

        """
    }
}
