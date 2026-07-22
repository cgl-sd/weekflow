# Weekflow 稳定性与架构整改任务书

> 仓库：`cgl-sd/weekflow`  
> 基准分支：`main`  
> 目标：在不重写现有 UI 和产品功能的前提下，优先修复可能导致数据错误、状态丢失、系统快捷键冲突、数据库升级失败和发布不稳定的问题，并逐步降低核心架构复杂度。

---

## 1. 执行原则

1. 数据安全优先于功能扩展。
2. 任何写入失败都不能让 UI 状态与磁盘状态长期分叉。
3. 明确区分“无时区的业务日期”和“绝对时间点”。
4. 一个用户操作必须具有清晰且原子的事务边界。
5. 历史数据库必须通过正式的版本迁移升级。
6. 不得静默吞掉存储、快捷键、通知和发布错误。
7. 优先小步重构，不一次性重写项目。
8. 每项高风险修改必须带自动化测试。

---

# 2. P0：下一次公开版本前必须完成

## P0-1：移除高冲突全局快捷键

### 问题

`GlobalDateShortcutService` 启动时无条件注册：

- `Shift + Space`
- `Shift + Left Arrow`
- `Shift + Right Arrow`

这些系统级组合会抢占其他应用中的文本选择和输入操作。

### 涉及文件

- `01_workspace/Sources/Weekflow/Services/GlobalDateShortcutService.swift`
- `01_workspace/Sources/Weekflow/App/WeekflowApp.swift`
- 快捷键设置及测试文件

### 修改要求

- 默认关闭全局快捷键。
- 禁止使用只有 `Shift` 的组合。
- 默认组合至少包含 `Command` 或 `Option`。
- 增加启用/关闭设置。
- 注册失败时显示明确状态，不能静默跳过。
- 配置变化时注销旧快捷键并重新注册。
- 应用退出时显式注销。

### 验收标准

- 默认安装后不拦截 `Shift + Left/Right`。
- 关闭功能后系统中不存在 Weekflow hotkey。
- 冲突时设置页能显示错误。
- 注册、重新注册、注销均有测试。

---

## P0-2：加固压缩数据解码

### 问题

`CompactDataCodec.decode` 信任 payload 头部声明的原始长度并直接分配 `Data(count:)`。损坏数据可能造成整数转换 trap、超大内存分配或强制解包崩溃。

### 涉及文件

- `01_workspace/Sources/Weekflow/Services/PersistenceRepository.swift`
- 持久化安全测试

### 修改要求

- 使用 `Int(exactly:)` 安全转换。
- 设置单条 payload 最大解压尺寸，例如 64 MB。
- 拒绝未知 marker、截断 header、空压缩内容、异常长度和长度不匹配。
- 不使用 `baseAddress!`。
- 给编码格式增加版本信息。
- 可选：增加 checksum。
- 所有异常转换为明确、可捕获的错误。

### 必须测试

- 空数据
- 只有 marker
- 未知 marker
- 截断 header
- header 声明 1 TB
- `UInt64.max`
- 空压缩内容
- 解压长度不匹配
- 随机损坏 payload
- 正常 raw/compressed payload

### 验收标准

任意损坏 payload 不会崩溃、不会触发超大内存分配，并能让 Store 进入只读保护状态。

---

## P0-3：发布前强制运行测试并建立 CI

### 涉及文件

- `script/build_and_run.sh`
- `.github/workflows/*.yml`

### 修改要求

- package 模式先执行：

```bash
swift test
swift build -c release
```

- 测试失败时不得生成 ZIP/DMG。
- GitHub Actions 覆盖 PR、`main` push 和 release tag。
- CI 至少执行 build、test、release build。
- Release workflow 增加 package 校验和 SHA-256。

### 验收标准

- 测试失败时 package 非零退出。
- PR 可见强制检查状态。
- CI 失败不能生成正式 release artifact。

---

## P0-4：修复打包脚本和应用命名

### 问题

当前 `APP_NAME=Weekflow`，但 Info.plist 中显示名为 `Workflow`；package 也会无条件杀掉正在运行的应用，且临时目录没有 `trap` 清理。

### 修改要求

- 所有名称统一为 `Weekflow`。
- package 模式不要执行 `pkill`。
- 仅 run/debug 模式按需关闭旧进程。
- 为 `mktemp -d` 增加 `trap` 清理。
- 版本号从 tag、环境变量或统一版本文件读取。
- package 后验证 Info.plist 的 ID、名称、版本、build number 和最低系统版本。

### 验收标准

- Finder 显示 `Weekflow`。
- package 不会杀掉用户进程。
- 任意失败不会残留临时目录。
- tag、app version 和 release 文件名一致。

---

# 3. P1：稳定版前必须完成

## P1-1：引入无时区业务日期 `LocalDay`

### 问题

任务安排日、每日计划、每日回顾、周开始日等本质上是无时区日期，但当前都使用 `Date`，并在各处用 `Calendar.current` 计算 `startOfDay`、唯一键和同日比较。

切换系统时区、旅行或夏令时边界可能导致：

- 任务跨日显示
- 同一天生成不同持久化 key
- 每日计划被删除再创建
- 自动分配撤销无法匹配日期
- 回顾与统计落入错误日期
- Repository 和 UI 使用不同 Calendar 状态

### 目标类型

```swift
struct LocalDay: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int
}

struct LocalTime: Codable, Hashable, Comparable, Sendable {
    let minutesSinceMidnight: Int
}
```

### 使用规则

使用 `LocalDay`：

- planned day
- assigned day
- daily planning day
- daily summary day
- goal start/end day
- execution week start
- completion credit day
- focus statistics day

继续使用 `Date`：

- `createdAt`、`updatedAt`
- timer `startedAt`
- transaction timestamp
- 真实日历事件时间点

使用 `LocalTime` 或分钟数：

- 每日计划开始时间
- 工作截止时间
- 任务计划钟点

### 修改要求

- 不再用 `timeIntervalSinceReferenceDate` 生成业务日期 key。
- 持久化 key 使用稳定 `YYYY-MM-DD`。
- Calendar/TimeZone 通过统一服务注入。
- 业务代码中不再散落 `Calendar.current`。
- 系统时区变化不能改变已存业务日期。

### 必须测试

- Asia/Shanghai → America/Los_Angeles
- UTC+14 → UTC-12
- DST 开始/结束日
- 应用运行中改变时区
- 改时区后保存、重启和读取
- 自动分配跨时区撤销
- 每日总结和周起始日跨时区

### 验收标准

同一个业务日期在任何系统时区下都保持相同 `LocalDay` 和持久化 key。

---

## P1-2：建立 SwiftData VersionedSchema 和 MigrationPlan

### 问题

当前自定义 `schemaVersion` metadata 不能替代 SwiftData 正式迁移。未来修改 `@Model` 字段、唯一约束或结构时，旧用户数据库可能打不开。

### 修改要求

- 冻结当前结构：

```swift
enum WeekflowSchemaV1: VersionedSchema { ... }
```

- 建立：

```swift
enum WeekflowMigrationPlan: SchemaMigrationPlan { ... }
```

- ModelContainer 必须使用 migration plan。
- 后续结构变化必须新增 V2/V3，并编写 lightweight 或 custom migration。
- Repository 记录当前 schema 版本、迁移结果和失败原因。
- 提交真实历史数据库 fixtures：空库、常规数据、归档/垃圾桶、自动分配、大数据和日期边界数据。

### 验收标准

- 旧数据库可自动升级。
- 所有 ID、关系、状态、日期和排序保持一致。
- 迁移失败不覆盖原库。
- CI 运行真实旧库升级测试。

---

## P1-3：建立统一事务边界和内存回滚

### 问题

当前多数操作先修改 Store 内存，再保存；保存失败后只停止后续写入，不回滚内存。UI 会显示成功，但重启后操作消失。

部分业务操作还包含多次独立保存，例如自动 assignment 转 manual 后再移动任务、daily plan 保存后再更新 CalendarEvent，可能部分提交。

### 目标流程

```text
用户命令
→ 在工作副本中计算完整状态
→ 校验领域不变量
→ 单事务写入
→ commit 成功
→ 发布 UI 状态
```

### 修改要求

- 新增 `PersistenceActor`，`ModelContext` 只在该 actor 内使用。
- 提供原子事务接口，例如 `performTransaction`。
- 保存失败时执行 context rollback，并恢复 Store 修改前快照。
- 自动分配、移动、撤销、daily plan 和 CalendarEvent 更新必须单事务。
- 禁止一个用户操作连续调用多个互不关联的 save API。
- 保存失败后不能允许用户继续静默编辑一个不会落盘的内存世界。

### 必须故障注入测试

- 第一次写入失败
- 中间步骤失败
- 最终 save 失败
- assignment 成功但 task 失败
- daily plan 成功但 event 失败
- 数据库锁定
- 磁盘满
- 只读目录

### 验收标准

任意失败后，Store 内存状态与重启后的磁盘状态一致，不存在部分提交。

---

## P1-4：修复计时时长高估

### 问题

当前每次 pause/flush 都对秒数向上取整，且最少记 1 分钟。1 秒暂停 100 次可能记录 100 分钟。

### 修改要求

- 内部统一存储秒：`actualSeconds`、`focusSeconds`。
- UI 展示时再转换为分钟。
- 多次暂停不能分别向上取整。
- 余秒应继续累计。
- 日报/周报的展示舍入规则集中定义。
- 旧分钟数据迁移为 `minutes * 60`。
- 任务计时和专注计时使用同一累计策略。

### 必须测试

- 1 秒暂停 100 次
- 30 + 30 秒
- 59 + 1 秒
- 61 秒
- 睡眠唤醒
- 快速启动取消
- task-linked focus
- 跨午夜计时

### 验收标准

暂停次数不影响总时长，统计只存在定义明确的展示舍入误差。

---

## P1-5：持久化 active timer session

### 问题

`TaskTimerSession` 只在内存中。退出、崩溃或强制结束可能丢失最后一段时间，并留下没有 session 的 `.inProgress` 任务。

### 修改要求

持久化：

- goalID
- taskID
- startedAt
- baseActualSeconds
- lastCheckpointAt
- timer type

应用启动时检测未结束 session，并执行明确恢复策略：自动恢复、询问补记或标记异常中断。退出、睡眠、唤醒和切换任务统一 checkpoint。

运行时计时使用 `ContinuousClock`；跨重启恢复使用 `Date`，异常长时段允许用户确认。

### 验收标准

- 正常退出不丢时间。
- 崩溃后可恢复或处理 session。
- 不存在永久 orphan `.inProgress`。
- 不存在 session 指向已删除任务。

---

## P1-6：限制 mutation history 增长

### 问题

每个 mutation operation 保存完整 `beforeValue` 和 `afterValue`，普通编辑历史没有清理上限，数据库会持续增长。

### 修改要求

- 自动分配撤销使用专用事务记录。
- 普通编辑不要永久保存完整前后 payload。
- 实现最大事务数、最大保留天数和定期清理。
- 可选实现字段级 delta 或 checkpoint。
- diagnostics 增加历史字节数、最旧事务日期和可清理数量。
- 清理不能破坏仍可撤销的事务。

### 必须测试

- 连续编辑 100,000 次
- 数据库增长上限
- 清理后读取
- 可撤销事务保留
- 清理中断后重启

### 验收标准

长期使用时 mutation history 不会无限膨胀，且清理策略可预测、可测试。

---

## P1-7：从全量 O(N) 保存改为真正增量

### 问题

修改一个任务仍会 fetch、遍历和编码大量 goal/task/assignment，交互式编辑可能阻塞 UI。

### 修改要求

- 提供单实体写入 API：saveGoal、saveTask、saveAssignment、deleteTask、saveDailyPlan。
- 批量操作使用 batch transaction。
- 文本输入使用 debounce。
- 持久化不得阻塞主线程。
- 只编码变化实体。
- 避免每次保存 fetch 全表。

### 建议性能目标

- 单任务标题编辑典型低于 50 ms。
- 10,000 个任务下单任务修改不随总量明显线性增长。
- Instruments 中无长时间主线程 fetch/encode。

---

# 4. P2：架构重构

## P2-1：消除 Goal/Subgoal/PrimaryTask/WeekTask 多份可变真相

### 问题

同一个业务概念同时存在于：

- `WeeklyGoal.subgoals`
- primary task 的 `subtasks`
- subgoal 对应的 `WeekTask`

双向同步容易丢失 `channelID`、描述、完成状态等字段。

### 修改要求

明确唯一 source of truth，可选择：

```text
WeeklyGoal → GoalItem/Subgoal → Task
```

或：

```text
WeeklyGoal → Task → Subtask
```

- primary task 和规划卡片改为只读 projection。
- 页面通过 `WeeklyPlanningProjection`、`DailyTaskProjection`、`ReviewProjection` 获取结构。
- 不再通过双向同步维护多份数组。
- channel、完成状态、描述等字段必须只有一个业务所有者。

### 验收标准

- 删除大量双向同步代码。
- 任意业务字段只有一个写入来源。
- 不再因同步丢失 channelID 或其他字段。

---

## P2-2：拆分 WeekflowStore

### 建议模块

```text
GoalService
TaskService
PlanningService
RecurringTaskService
FocusService
ReviewService
ArchiveService
AutomaticDistributionService
ClipboardService
```

### 修改要求

- `WeekflowStore` 只组合 feature state、调用 application service、发布 UI 状态。
- 业务服务通过协议依赖 persistence。
- 服务不依赖 SwiftUI。
- Store 明确标记：

```swift
@MainActor
@Observable
final class WeekflowStore
```

- 后台存储由 PersistenceActor 管理。

### 验收标准

- `WeekflowStore.swift` 体积显著下降。
- 每个业务模块可独立测试。
- 业务逻辑不依赖 View 生命周期。

---

## P2-3：拆分 ContentView 和内部通知总线

### 修改要求

新增：

- `AppCoordinator`
- `NavigationStore`
- `CommandRouter`

应用内部命令使用类型化 API，NotificationCenter 只保留真正的系统事件。多窗口命令必须具有目标窗口或 active scene 语义。

### 验收标准

- ContentView 主要负责布局。
- 快捷键和菜单命令由 CommandRouter 处理。
- 多窗口不会重复执行同一命令。
- 导航逻辑可独立测试。

---

## P2-4：不要覆盖 SwiftUI.Button 类型名

将模块级自定义 `Button` 改名为：

- `WeekflowButton`
- `InteractiveButton`
- `CursorButton`

或使用 `ButtonStyle`、ViewModifier、Environment 统一鼠标手型。

### 验收标准

- 项目中不再定义与 SwiftUI 同名的 `Button`。
- 按钮交互行为保持一致。

---

# 5. 存储初始化与迁移验证

## 5.1 启动阶段检查存储健康

`LocalStorage.init` 不再使用 `try?` 吞掉目录创建错误。

启动时检查：

- Application Support 可创建
- Database 路径确实是目录
- 可写
- 可创建临时文件
- 可原子替换
- 数据库可打开

失败时进入明确的只读恢复界面，而不是先显示正常空白应用。

## 5.2 迁移后比较完整内容

旧 JSON 迁移不能只比较数量。必须比较 canonical snapshot：

- IDs
- goal-task 关系
- task-subgoal 关系
- assignments 和 placement mask
- lifecycle state
- channelID
- sortOrder
- archive/trash
- focus totals
- daily review content

允许的规范化仅包括 assignedDates 去重、LocalDay 转换和明确的旧字段默认值。

---

# 6. 正式 macOS 发布链路

当前 ad-hoc 签名仅适合 preview。正式 release 流程应为：

```text
测试
→ Release build
→ Developer ID Application 签名
→ Hardened Runtime
→ Notarization
→ Staple
→ codesign verify
→ spctl verify
→ ZIP/DMG
→ SHA-256
→ GitHub Release
```

### 修改要求

- 正式 release 不使用 `codesign --sign -`。
- 配置 Developer ID identity。
- 启用 hardened runtime。
- 明确 entitlements。
- notarization 后 staple。
- 验证：

```bash
codesign --verify --deep --strict
spctl -a -vv
```

- 本地 preview package 和正式 release package 分离。
- secrets 仅通过 CI secret 管理。

### 验收标准

- 正式 release 可通过 Gatekeeper。
- 用户不需要右键 Open 绕过。
- ZIP 和 DMG 来自同一个已签名、公证的 app artifact。

---

# 7. 稳定性测试总表

## 日期和时区

- [ ] Asia/Shanghai → America/Los_Angeles
- [ ] UTC+14 → UTC-12
- [ ] DST 开始日和结束日
- [ ] 应用运行中切换时区
- [ ] 跨时区保存和重启
- [ ] 自动分配跨时区撤销
- [ ] 每日总结保持业务日期

## 数据损坏

- [ ] 非法压缩 marker
- [ ] 截断 header
- [ ] 超大原始长度
- [ ] 空压缩内容
- [ ] 解压长度不一致
- [ ] 随机损坏 payload
- [ ] 损坏数据不导致进程崩溃

## 事务

- [ ] 第一步写入失败
- [ ] 中间步骤失败
- [ ] 最终 save 失败
- [ ] rollback 后内存恢复
- [ ] 自动分配部分失败
- [ ] daily plan/event 部分失败
- [ ] 磁盘满、锁定、只读

## 计时

- [ ] 1 秒暂停 100 次
- [ ] 30 + 30 秒
- [ ] 59 + 1 秒
- [ ] 跨午夜
- [ ] 睡眠唤醒
- [ ] 正常退出恢复
- [ ] 崩溃恢复
- [ ] orphan `.inProgress` 修复

## 迁移

- [ ] V1 → V2 空库
- [ ] 常规数据
- [ ] 归档和垃圾桶
- [ ] 自动分配事务
- [ ] 大数据
- [ ] 内容错误但数量相同
- [ ] 迁移失败原库不变

## 性能

- [ ] 10,000 个任务启动
- [ ] 10,000 个任务单任务编辑
- [ ] 100,000 次 mutation history
- [ ] history 清理
- [ ] 数据库体积上限
- [ ] 主线程无长时间阻塞

## 系统集成

- [ ] 全局快捷键冲突
- [ ] 关闭后完全注销
- [ ] 多窗口命令不重复执行
- [ ] 通知权限拒绝
- [ ] 应用退出生命周期

---

# 8. 推荐实施顺序

## 第一阶段：立即止血

1. 全局快捷键。
2. CompactDataCodec。
3. package 前测试和基础 CI。
4. 应用命名、版本和临时目录。
5. 启动存储健康检查。
6. 计时舍入。
7. active timer 退出保存。

## 第二阶段：数据基础

1. 引入 `LocalDay`。
2. 建立 Calendar/TimeZone 依赖。
3. 迁移业务日期。
4. 建立 VersionedSchema 和 MigrationPlan。
5. 提交历史数据库 fixtures。

## 第三阶段：事务与性能

1. PersistenceActor。
2. Unit of Work。
3. Store 回滚。
4. 合并跨实体操作。
5. 增量写入和 debounce。
6. 限制 mutation history。

## 第四阶段：领域架构

1. 明确 Goal/Subgoal/Task source of truth。
2. 引入 projections。
3. 删除双向同步。
4. 拆分 WeekflowStore。
5. 拆分 ContentView。
6. 替换 NotificationCenter 内部总线。
7. 重命名自定义 Button。

## 第五阶段：正式发布

1. Developer ID 签名。
2. Hardened Runtime。
3. Notarization 和 staple。
4. Gatekeeper 验证。
5. 自动 release workflow。
6. checksum 和恢复备份。

---

# 9. 本轮非目标

本轮不要求：

- 重写整个 SwiftUI UI
- 更换 SwiftData 为第三方数据库
- 接入云同步或外部 AI
- 大规模重新设计产品交互
- 一次性完成所有模块拆分

优先保证：数据不漂移、写入不部分提交、旧库可升级、计时不失真、异常后可恢复、发布可验证。

---

# 10. 完成定义

- [ ] 不再注册高冲突 Shift 全局快捷键
- [ ] 损坏 payload 不会崩溃或分配超大内存
- [ ] 业务日期不受系统时区变化影响
- [ ] SwiftData 使用正式版本化迁移
- [ ] 保存失败后 UI 和磁盘一致
- [ ] 自动分配和每日计划具备统一事务
- [ ] 计时内部使用秒，暂停次数不影响总时长
- [ ] active timer 可跨退出或崩溃恢复
- [ ] mutation history 有上限和清理策略
- [ ] 单任务编辑不再全量 O(N) 保存
- [ ] WeekflowStore 开始按业务模块拆分
- [ ] CI 对 PR 和 main 强制构建与测试
- [ ] 正式 release 使用签名和公证流程
- [ ] 所有高风险场景均有自动化测试

---

# 11. PR 交付要求

每个整改 PR 必须说明：

1. 修复的问题
2. 设计选择
3. 数据迁移影响
4. 新增或修改的测试
5. 回滚方案
6. 性能影响
7. 用户可见变化
8. 是否影响现有本地数据
9. 是否更新 README 或 release notes

禁止用一个超大 PR 同时重构所有模块。按阶段拆分为可独立验证、可独立回滚的 PR。
