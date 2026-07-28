import Foundation

/// Explicit development-only data. Production stores never load this fixture
/// unless the caller opts in with `developmentFixture:`.
struct WeekflowDevelopmentFixture {
    static let stageOneIdentifier = "weekflow-v4-stage-1"
    static let marketingIdentifier = "weekflow-marketing-2026-07-28"

    static let marketingReferenceDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 28, hour: 12)
        )!
    }()

    let identifier: String
    let referenceDate: Date
    let goals: [WeeklyGoal]
    let channels: [TaskChannel]
    let calendarEvents: [CalendarEvent]
    let focusRecords: [FocusRecord]
    let dailySummaries: [DailySummary]

    init(
        identifier: String,
        referenceDate: Date,
        goals: [WeeklyGoal],
        channels: [TaskChannel],
        calendarEvents: [CalendarEvent],
        focusRecords: [FocusRecord] = [],
        dailySummaries: [DailySummary] = []
    ) {
        self.identifier = identifier
        self.referenceDate = referenceDate
        self.goals = goals
        self.channels = channels
        self.calendarEvents = calendarEvents
        self.focusRecords = focusRecords
        self.dailySummaries = dailySummaries
    }

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
            calendarEvents: [],
            focusRecords: [],
            dailySummaries: []
        )
    }

    /// Stable, presentation-ready content used only for public product imagery.
    /// The fixed Tuesday reference makes screenshots reproducible and lets the
    /// story continue naturally through Wednesday and Thursday.
    static func marketing(
        referenceDate: Date = marketingReferenceDate,
        calendar: Calendar = marketingCalendar
    ) -> WeekflowDevelopmentFixture {
        let tuesday = calendar.startOfDay(for: referenceDate)
        let monday = calendar.date(byAdding: .day, value: -1, to: tuesday) ?? tuesday
        let wednesday = calendar.date(byAdding: .day, value: 1, to: tuesday) ?? tuesday
        let thursday = calendar.date(byAdding: .day, value: 2, to: tuesday) ?? tuesday
        let sunday = calendar.date(byAdding: .day, value: 5, to: tuesday) ?? thursday
        let businessCalendar = BusinessCalendar(calendar: calendar)

        let narrativeID = fixtureUUID(1_101)
        let recordingID = fixtureUUID(1_102)
        let publishID = fixtureUUID(1_103)
        let weeklyOutcomesID = fixtureUUID(1_201)
        let deepWorkID = fixtureUUID(1_202)
        let reflectionID = fixtureUUID(1_203)

        var launchGoal = WeeklyGoal(
            id: fixtureUUID(1_100),
            title: "发布 Weekflow 产品演示",
            outcome: "让第一次访问的人在三分钟内理解从周目标到每日执行的完整流程",
            startDate: monday,
            endDate: sunday,
            channelID: "product",
            subgoals: [
                GoalSubgoal(
                    id: narrativeID,
                    title: "确定演示主线",
                    detail: "聚焦周目标、每日计划、专注与复盘的闭环",
                    channelID: "product",
                    isCompleted: true
                ),
                GoalSubgoal(
                    id: recordingID,
                    title: "完成核心流程录制",
                    detail: "用清晰截图和短动效展示真实操作",
                    channelID: "content"
                ),
                GoalSubgoal(
                    id: publishID,
                    title: "上线产品介绍页",
                    detail: "检查桌面与移动端阅读体验",
                    channelID: "product"
                )
            ],
            tasks: [
                makeTask(
                    1_111,
                    "梳理演示页面的信息主线",
                    on: tuesday,
                    at: (9, 0),
                    estimated: 60,
                    actual: 65,
                    status: .completed,
                    channel: "product",
                    priority: .must,
                    subgoalID: narrativeID,
                    subtasks: [
                        TaskSubtask(id: fixtureUUID(1_151), title: "明确一句话定位", completed: true),
                        TaskSubtask(id: fixtureUUID(1_152), title: "排出演示章节", completed: true)
                    ],
                    calendar: calendar
                ),
                makeTask(
                    1_112,
                    "制作首页高清界面素材",
                    on: tuesday,
                    at: (14, 0),
                    estimated: 90,
                    actual: 40,
                    status: .inProgress,
                    channel: "content",
                    priority: .must,
                    subgoalID: recordingID,
                    subtasks: [
                        TaskSubtask(id: fixtureUUID(1_153), title: "整理演示数据", completed: true),
                        TaskSubtask(id: fixtureUUID(1_154), title: "导出 2× 截图"),
                        TaskSubtask(id: fixtureUUID(1_155), title: "裁切首屏重点区域")
                    ],
                    calendar: calendar
                ),
                makeTask(
                    1_113,
                    "录制周目标到每日执行流程",
                    on: wednesday,
                    at: (10, 0),
                    estimated: 90,
                    channel: "content",
                    priority: .should,
                    calendar: calendar
                ),
                makeTask(
                    1_114,
                    "发布演示页面并完成多尺寸检查",
                    on: thursday,
                    at: (15, 0),
                    estimated: 75,
                    channel: "product",
                    priority: .must,
                    subgoalID: publishID,
                    calendar: calendar
                )
            ],
            milestones: [
                Milestone(id: fixtureUUID(1_161), title: "演示页面可公开预览", date: thursday, type: .delivery)
            ],
            isPinned: true,
            sortOrder: 0
        )
        launchGoal.startDay = LocalDay(monday, calendar: calendar)
        launchGoal.endDay = LocalDay(sunday, calendar: calendar)

        var rhythmGoal = WeeklyGoal(
            id: fixtureUUID(1_200),
            title: "建立稳定的每周执行节奏",
            outcome: "每天围绕关键结果工作，并用简短回顾为下一天留出清晰起点",
            startDate: monday,
            endDate: sunday,
            channelID: "personal",
            subgoals: [
                GoalSubgoal(
                    id: weeklyOutcomesID,
                    title: "确定本周三个关键结果",
                    detail: "目标足够具体，能直接拆成每日行动",
                    channelID: "personal",
                    isCompleted: true
                ),
                GoalSubgoal(
                    id: deepWorkID,
                    title: "完成两次无干扰专注",
                    detail: "把最清醒的时间留给高价值工作",
                    channelID: "research",
                    isCompleted: true
                ),
                GoalSubgoal(
                    id: reflectionID,
                    title: "沉淀一份可复用的周复盘",
                    detail: "记录有效做法和下周要调整的节奏",
                    channelID: "personal"
                )
            ],
            tasks: [
                makeTask(
                    1_211,
                    "确认本周三个关键结果",
                    on: tuesday,
                    at: (8, 0),
                    estimated: 45,
                    actual: 35,
                    status: .completed,
                    channel: "personal",
                    priority: .should,
                    subgoalID: weeklyOutcomesID,
                    calendar: calendar
                ),
                makeTask(
                    1_212,
                    "50 分钟专注：完善核心交互",
                    on: tuesday,
                    at: (11, 0),
                    estimated: 50,
                    actual: 50,
                    status: .completed,
                    channel: "research",
                    priority: .must,
                    subgoalID: deepWorkID,
                    calendar: calendar
                ),
                makeTask(
                    1_213,
                    "整理访客最关心的五个问题",
                    on: tuesday,
                    at: (16, 30),
                    estimated: 45,
                    channel: "research",
                    priority: .later,
                    subgoalID: reflectionID,
                    calendar: calendar
                ),
                makeTask(
                    1_214,
                    "验证计划、专注与回顾的衔接",
                    on: wednesday,
                    at: (13, 30),
                    estimated: 75,
                    channel: "product",
                    priority: .should,
                    calendar: calendar
                ),
                makeTask(
                    1_215,
                    "完成本周复盘并安排下周",
                    on: thursday,
                    at: (17, 0),
                    estimated: 60,
                    channel: "personal",
                    priority: .should,
                    calendar: calendar
                )
            ],
            milestones: [
                Milestone(id: fixtureUUID(1_261), title: "周中节奏检查", date: wednesday, type: .checkpoint)
            ],
            sortOrder: 1
        )
        rhythmGoal.startDay = LocalDay(monday, calendar: calendar)
        rhythmGoal.endDay = LocalDay(sunday, calendar: calendar)

        return WeekflowDevelopmentFixture(
            identifier: marketingIdentifier,
            referenceDate: tuesday,
            goals: [launchGoal, rhythmGoal],
            channels: [
                TaskChannel(id: "product", title: "产品设计", colorName: "orange", isDefault: true, iconName: "sparkles"),
                TaskChannel(id: "content", title: "内容创作", colorName: "purple", iconName: "doc.text.image"),
                TaskChannel(id: "research", title: "用户研究", colorName: "blue", iconName: "person.2"),
                TaskChannel(id: "personal", title: "个人成长", colorName: "green", isPersonal: true, countsTowardWorkload: false, iconName: "leaf")
            ],
            calendarEvents: [
                CalendarEvent(
                    id: fixtureUUID(1_301),
                    title: "演示页面设计评审",
                    startDate: calendar.date(bySettingHour: 13, minute: 0, second: 0, of: tuesday) ?? tuesday,
                    durationMinutes: 45,
                    colorName: "orange"
                ),
                CalendarEvent(
                    id: fixtureUUID(1_302),
                    title: "核心流程录制",
                    startDate: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: wednesday) ?? wednesday,
                    durationMinutes: 90,
                    colorName: "purple"
                )
            ],
            focusRecords: [
                FocusRecord(id: fixtureUUID(1_401), date: monday, modeID: "meditation", minutes: 15, calendar: businessCalendar),
                FocusRecord(id: fixtureUUID(1_402), date: tuesday, modeID: "study", minutes: 50, calendar: businessCalendar)
            ],
            dailySummaries: [
                DailySummary(
                    id: fixtureUUID(1_501),
                    date: monday,
                    content: "## 今日进展\n确定了本周三项关键结果，也为演示页面整理好了素材清单。",
                    updatedAt: monday,
                    calendar: businessCalendar
                ),
                DailySummary(
                    id: fixtureUUID(1_502),
                    date: tuesday,
                    content: "## 今日进展\n演示主线已经成形，高清素材正在制作。明天先录制核心流程，再补充常见问题。",
                    updatedAt: tuesday,
                    calendar: businessCalendar
                )
            ]
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
            calendarEvents: [],
            focusRecords: [],
            dailySummaries: []
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
        subgoalID: GoalSubgoal.ID? = nil,
        subtasks: [TaskSubtask] = [],
        calendar: Calendar
    ) -> WeekTask {
        let startTime = time.flatMap {
            calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: date)
        }
        var task = WeekTask(
            id: fixtureUUID(identifier),
            title: title,
            plannedDate: date,
            startTime: startTime,
            dueDate: date,
            estimatedMinutes: estimated,
            actualMinutes: actual,
            status: status,
            subgoalID: subgoalID,
            channelID: channel,
            priority: priority,
            sourceType: subgoalID == nil ? .native : .weeklyObjective,
            subtasks: subtasks,
            createdAt: date,
            updatedAt: date,
            sortOrder: identifier
        )
        // WeekTask's compatibility initializer uses the process-wide calendar.
        // Rewrite civil date fields from the explicit fixture calendar so the
        // marketing data is identical on every machine and time zone.
        let day = LocalDay(date, calendar: calendar)
        task.plannedDay = day
        task.dueDay = day
        task.startLocalTime = startTime.map { LocalTime($0, calendar: calendar) }
        task.startTimeDay = startTime == nil ? nil : day
        return task
    }

    private static var marketingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
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
        let store = WeekflowStore(
            storage: storage,
            developmentFixture: .regression(referenceDate: referenceDate)
        )
        store.synchronousPersistence = true
        return store
    }
}
