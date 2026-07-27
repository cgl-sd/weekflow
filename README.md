# Weekflow

**把一周真正想完成的事，变成每天可以执行的安排。**

Weekflow 是一款原生 macOS 周计划与执行应用。它从本周目标出发，把目标拆成任务、安排到每天，再用专注计时和回顾形成完整闭环。

<p align="center">
  <img src="assets/readme/home.png" alt="Weekflow 首页" width="720" />
</p>

## 主要功能

- **周目标规划**：建立目标和子目标，管理预计时间、完成数量、频道与进度。
- **任务池与每日分配**：手动拖拽或自动分配任务，并可撤销自动分配结果。
- **每日计划**：选择明日事项、设置截止时间，并在时间轴中安排任务。
- **专注执行**：记录任务实际投入，支持禅定、学习、休闲等专注模式。
- **每日与每周回顾**：查看任务完成、时间投入、频道分布和目标进度。
- **归档与恢复**：归档、垃圾桶和彻底删除具有明确边界，重要操作需要确认。

<table>
  <tr>
    <td width="50%" align="center">
      <img src="assets/readme/weekly-planning.png" alt="周目标规划" width="440" />
    </td>
    <td width="50%" align="center">
      <img src="assets/readme/daily-planning.png" alt="每日计划" width="440" />
    </td>
  </tr>
  <tr>
    <td align="center">周目标、任务池与每日分配</td>
    <td align="center">每日计划与时间轴</td>
  </tr>
</table>

<p align="center">
  <img src="assets/readme/focus-mode.png" alt="Weekflow 专注模式" width="600" />
</p>

## 系统要求

- macOS 14 或更高版本
- Apple Silicon 或 Intel Mac
- 不需要登录账号，不依赖云端服务

## 数据与隐私

Weekflow 本地优先，不包含广告、分析统计或遥测 SDK。

- 正式版数据保存在 macOS 沙盒目录 `~/Library/Containers/com.weekflow.app/Data/Library/Application Support/Weekflow`。
- DEBUG 构建只使用项目内的 `01_workspace/.data`，不会读取正式版数据；该目录不会提交到 Git。
- 安装包和 Git 仓库均不包含用户数据，首次运行时才创建本地存储。
- 只有用户主动点击“检查更新”时才连接 GitHub，且不会上传任务、计划或专注记录。
- 当前不接入 iCloud、系统日历、提醒事项或 AI API。
- 数据库升级前会生成可恢复备份；导入完整归档前会校验并备份现有数据。

完整说明见 [隐私说明](PRIVACY.md)。

## 开发

Weekflow 使用 Swift、SwiftUI、SwiftData 和 macOS 系统框架构建，没有第三方 Swift Package 运行时依赖。

```bash
cd 01_workspace
swift build
swift test
```

从仓库根目录构建并运行：

```bash
./script/build_and_run.sh
```

执行发布前本地验证：

```bash
./script/build_and_run.sh --verify
```

生成仅供本机测试的 ad-hoc ZIP 和 DMG：

```bash
./script/build_and_run.sh --package
```

正式公开发行还需要 Apple Developer ID 证书和公证凭据。发布脚本只允许从干净工作树和与 `VERSION` 完全一致的 Git 标签运行：

```bash
WEEKFLOW_DEVELOPER_ID="Developer ID Application: …" \
WEEKFLOW_NOTARY_PROFILE=weekflow-local \
./script/build_and_run.sh --release
```

## 版本

当前产品基线为 **Weekflow 1.0.0**。后续版本从此基线继续迭代；每版变化记录在 [RELEASE_NOTES.md](RELEASE_NOTES.md)。
