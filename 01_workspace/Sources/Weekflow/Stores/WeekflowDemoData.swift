import Foundation

/// Explicit development-only data. Production stores never load this fixture
/// unless the caller opts in with `developmentFixture:`.
struct WeekflowDevelopmentFixture {
    static let stageOneIdentifier = "weekflow-v4-stage-1"

    let identifier: String
    let referenceDate: Date
    let goals: [WeeklyGoal]
    let channels: [TaskChannel]
    let calendarEvents: [CalendarEvent]

    static func stageOne(
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> WeekflowDevelopmentFixture {
        let sunday = startOfFixtureWeek(containing: referenceDate, calendar: calendar)
        let monday = calendar.date(byAdding: .day, value: 1, to: sunday) ?? sunday
        let tuesday = calendar.date(byAdding: .day, value: 2, to: sunday) ?? sunday
        let nextWeekMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: sunday) ?? tuesday

        var goal = WeeklyGoal(
            id: fixtureUUID(400),
            title: "V4 交互联动验收",
            outcome: "验证任务卡、纵向滚动、计时信息和跨页面联动",
            startDate: sunday,
            endDate: weekEnd,
            channelID: "work"
        )

        goal.tasks = [
            makeTask(1, "整理周日执行重点", on: sunday, at: (8, 30), estimated: 45, actual: 20, status: .completed, channel: "personal", priority: .should, calendar: calendar),
            makeTask(2, "核对任务卡右侧预计时间", on: sunday, estimated: 90, channel: "work", priority: .must, calendar: calendar),
            makeTask(3, "准备周计划任务池材料", on: sunday, at: (11, 0), estimated: 60, channel: "presentations", priority: .should, calendar: calendar),
            makeTask(4, "完成周日复盘记录", on: sunday, at: (17, 30), estimated: 30, channel: "personal", priority: .later, calendar: calendar),

            makeTask(5, "确认周一演示流程", on: monday, at: (9, 0), estimated: 60, channel: "work", priority: .must, calendar: calendar),
            makeTask(6, "阅读联动设计说明", on: monday, estimated: 75, channel: "research", priority: .should, calendar: calendar),
            makeTask(7, "整理任务拖拽验收清单", on: monday, at: (14, 0), estimated: 45, channel: "presentations", priority: .should, calendar: calendar),
            makeTask(8, "记录周一测试反馈", on: monday, at: (16, 30), estimated: 30, channel: "personal", priority: .later, calendar: calendar),
            makeTask(22, "【本轮演示】普通任务 · 无开始时间", on: monday, estimated: 35, channel: "personal", priority: .none, calendar: calendar),
            makeTask(23, "【本轮演示】紧急任务 · 已设开始时间", on: monday, at: (10, 15), estimated: 50, channel: "work", priority: .must, calendar: calendar),
            makeTask(26, "检查首页任务卡滚动区域", on: monday, at: (11, 30), estimated: 40, channel: "work", priority: .should, calendar: calendar),
            makeTask(27, "滚动查看靠后的任务卡", on: monday, estimated: 30, channel: "research", priority: .none, calendar: calendar),
            makeTask(28, "确认滚动条与添加任务右侧对齐", on: monday, at: (15, 0), estimated: 45, channel: "presentations", priority: .must, calendar: calendar),
            makeTask(29, "验证滚动后任务卡宽度稳定", on: monday, estimated: 25, channel: "personal", priority: .later, calendar: calendar),

            makeTask(9, "检查大量任务下计时信息是否完整显示", on: tuesday, at: (8, 0), estimated: 60, channel: "work", priority: .must, calendar: calendar),
            makeTask(10, "验证有开始时间的任务卡", on: tuesday, at: (9, 15), estimated: 45, channel: "research", priority: .should, calendar: calendar),
            makeTask(11, "验证无开始时间的任务卡不会保留空行", on: tuesday, estimated: 90, channel: "study", priority: .should, calendar: calendar),
            makeTask(12, "拖动任务到另一天", on: tuesday, at: (10, 30), estimated: 30, channel: "work", priority: .must, calendar: calendar),
            makeTask(13, "打开任务计时弹窗", on: tuesday, estimated: 120, channel: "presentations", priority: .should, calendar: calendar),
            makeTask(14, "核对不同 Channel 的颜色", on: tuesday, at: (13, 0), estimated: 40, channel: "research", priority: .later, calendar: calendar),
            makeTask(15, "检查任务卡圆角与阴影", on: tuesday, estimated: 50, channel: "personal", priority: .none, calendar: calendar),
            makeTask(16, "滚动到任务列底部", on: tuesday, at: (15, 0), estimated: 35, channel: "work", priority: .should, calendar: calendar),
            makeTask(17, "确认滚动条不会压缩卡片宽度", on: tuesday, estimated: 95, channel: "study", priority: .must, calendar: calendar),
            makeTask(18, "完成阶段一视觉验收", on: tuesday, at: (17, 0), estimated: 60, channel: "presentations", priority: .must, calendar: calendar),
            makeTask(24, "【本轮演示】低优先级任务", on: tuesday, estimated: 40, channel: "research", priority: .later, calendar: calendar),
            makeTask(25, "【本轮演示】实际与预计时间对照", on: tuesday, at: (14, 30), estimated: 75, actual: 28, status: .inProgress, channel: "presentations", priority: .should, calendar: calendar),
            WeekTask(id: fixtureUUID(19), title: "整理每日计划交互说明", executionWeekStart: nextWeekMonday, estimatedMinutes: 60, channelID: "work", priority: .must, sourceType: .weeklyObjective),
            WeekTask(id: fixtureUUID(20), title: "准备导师同步材料", estimatedMinutes: 90, channelID: "presentations", priority: .should, sourceType: .weeklyObjective),
            WeekTask(id: fixtureUUID(21), title: "复核研究资料摘要", estimatedMinutes: 45, channelID: "research", priority: .later, sourceType: .weeklyObjective)
        ]

        return WeekflowDevelopmentFixture(
            identifier: stageOneIdentifier,
            referenceDate: sunday,
            goals: [goal],
            channels: TaskChannel.defaults,
            calendarEvents: []
        )
    }

    /// Existing regression tests need tasks on their supplied reference day.
    /// This remains explicit and never participates in normal app startup.
    static func regression(
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> WeekflowDevelopmentFixture {
        let today = calendar.startOfDay(for: referenceDate)
        let endDate = calendar.date(byAdding: .day, value: 6, to: today) ?? today
        var goal = WeeklyGoal(
            id: fixtureUUID(500),
            title: "产品原型演示",
            outcome: "为自动回归提供确定的本地任务",
            startDate: today,
            endDate: endDate,
            channelID: "work"
        )
        goal.tasks = regressionTodaySchedule(referenceDate: today, calendar: calendar) + [
            WeekTask(id: fixtureUUID(506), title: "准备演示开场", estimatedMinutes: 60, channelID: "work", priority: .should, sourceType: .weeklyObjective),
            WeekTask(id: fixtureUUID(507), title: "确认演示反馈问题", estimatedMinutes: 60, channelID: "research", priority: .later, sourceType: .weeklyObjective)
        ]
        return WeekflowDevelopmentFixture(
            identifier: "weekflow-regression",
            referenceDate: today,
            goals: [goal],
            channels: TaskChannel.defaults,
            calendarEvents: []
        )
    }

    static func regressionTodaySchedule(
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> [WeekTask] {
        let today = calendar.startOfDay(for: referenceDate)
        return [
            makeTask(501, "整理今日重点", on: today, at: (8, 30), estimated: 45, status: .completed, channel: "personal", priority: .should, calendar: calendar),
            makeTask(502, "完善 Weekflow 看板", on: today, at: (9, 30), estimated: 90, channel: "work", priority: .must, calendar: calendar),
            makeTask(503, "准备产品演示材料", on: today, at: (11, 30), estimated: 60, channel: "presentations", priority: .must, calendar: calendar),
            makeTask(504, "阅读研究资料", on: today, at: (14, 0), estimated: 75, channel: "research", priority: .should, calendar: calendar),
            makeTask(505, "每日回顾与复盘", on: today, at: (17, 0), estimated: 30, channel: "personal", priority: .later, calendar: calendar)
        ]
    }

    private static func startOfFixtureWeek(containing date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let daysSinceSunday = max(calendar.component(.weekday, from: start) - 1, 0)
        return calendar.date(byAdding: .day, value: -daysSinceSunday, to: start) ?? start
    }

    private static func makeTask(
        _ identifier: Int,
        _ title: String,
        on date: Date,
        at time: (hour: Int, minute: Int)? = nil,
        estimated: Int,
        actual: Int = 0,
        status: TaskStatus = .planned,
        channel: String,
        priority: TaskPriority,
        calendar: Calendar
    ) -> WeekTask {
        let startTime = time.flatMap {
            calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: date)
        }
        return WeekTask(
            id: fixtureUUID(identifier),
            title: title,
            plannedDate: date,
            startTime: startTime,
            dueDate: date,
            estimatedMinutes: estimated,
            actualMinutes: actual,
            status: status,
            channelID: channel,
            priority: priority,
            createdAt: date,
            updatedAt: date,
            sortOrder: identifier
        )
    }

    private static func fixtureUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }
}

extension WeekflowStore {
    static func testing(
        storage: LocalStorage,
        referenceDate: Date = .now
    ) -> WeekflowStore {
        WeekflowStore(
            storage: storage,
            developmentFixture: .regression(referenceDate: referenceDate)
        )
    }
}
