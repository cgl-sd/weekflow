# Weekflow

**Turn what matters this week into a plan you can execute every day.**

[简体中文](README.md) · [English](README.en.md)

Weekflow is a native weekly planning and execution app for macOS. Instead of starting with disconnected to-dos, it begins with weekly goals, turns subgoals into a task pool, distributes work across the week, and closes the loop with focus tracking and reviews.

![Weekflow home view with tasks organized by day](assets/readme/home.png)

## What it supports

- **Weekly goals**: Define goals and subgoals while tracking estimates, completion, channels, and progress.
- **Task pool and daily allocation**: Generate work from weekly goals, assign or drag it onto specific days, or use reversible automatic allocation.
- **Daily planning**: Select tomorrow's work, set a work cutoff, and review the calendar timeline on the same screen.
- **Daily execution**: Organize tasks by date, schedule start times, compare estimates with actual effort, and group work by Channel.
- **Focus mode**: Track meditation, study, and rest sessions as part of daily and weekly time statistics.
- **Daily and weekly reviews**: Review completed work, time investment, channel distribution, and goal progress before archiving or carrying work forward.
- **Archive and trash**: Archived and deleted items have separate lifecycles, recovery paths, and explicit permanent-deletion confirmation.

## What it changes

Weekflow keeps goals, tasks, dates, effort, and reviews in one connected data flow. Weekly allocations appear in daily planning; unplanned tasks created during the day remain isolated from weekly goals; completion, actual time, and focus sessions feed directly into review statistics.

<table>
  <tr>
    <td><img src="assets/readme/weekly-planning.png" alt="Weekly goals, task pool, and daily allocation" /></td>
    <td><img src="assets/readme/daily-planning.png" alt="Daily planning and calendar timeline" /></td>
  </tr>
  <tr>
    <td align="center">Weekly goals → Task pool → Daily allocation</td>
    <td align="center">Select tomorrow's work and place it on the timeline</td>
  </tr>
</table>

## A typical use case

Suppose this week's goal is to finish a research presentation:

1. Create three subgoals: collect sources, shape the narrative, and build the deck.
2. Weekflow creates one task-pool card for each subgoal and records its estimate.
3. Assign research to Monday, the narrative to Tuesday, and slides to Wednesday. Remaining work can be distributed automatically across available days.
4. Execute from the home view and use Focus Mode to record real effort.
5. Review each day, then compare plan and reality at the end of the week. Carry unfinished work forward or archive completed goals.

## What makes it different

- **Goal-driven**: Weekly work always traces back to a goal or subgoal instead of living as an isolated to-do.
- **Two weekly views**: Manage work in a structured board or inspect goal-to-task-to-day relationships in the relationship map.
- **One source of truth**: Home, daily planning, weekly planning, and reviews all read the same task records.
- **Recoverable actions**: Automatic allocation is reversible, while archive, trash, and permanent deletion have explicit boundaries.
- **Native and local-first**: Built with SwiftUI and SwiftData, with no external service required for core use.
- **Customizable**: Configure channels, theme colors, progress bars, chart palettes, and task-card presentation.

## Focus Mode

![Weekflow Focus Mode](assets/readme/focus-mode.png)

Focus sessions contribute to actual task time and review statistics while preserving per-mode duration records.

## System and data

- Requires macOS 14 or later.
- Installed release builds store user data in `~/Library/Application Support/Weekflow`.
- Development DEBUG builds use only `01_workspace/.data` inside the project for business data and never read or write installed-app data; Git ignores that directory.
- Development builds use the separate bundle identifier `com.weekflow.app.debug`; installed release builds use `com.weekflow.app`, so macOS-managed window and UI preferences cannot overlap either.
- Release archives contain no user data; local storage is created on first launch.
- The current version does not connect to iCloud, Apple Calendar, Reminders, or external AI APIs.
- Planned days, daily summaries, and week boundaries use timezone-free business dates, so travel or a system timezone change does not rewrite an existing plan.
- Weekflow creates a recoverable backup before SwiftData upgrades. Corruption or migration failure opens read-only protection instead of replacing the original database with empty data.

## Download

Download the latest macOS DMG or ZIP from [GitHub Releases](https://github.com/cgl-sd/weekflow/releases/latest). Formal release artifacts are signed with Developer ID, use Hardened Runtime, are notarized by Apple, and include `SHA256SUMS`. Open the DMG and drag `Weekflow.app` to Applications, or extract the ZIP and move the app manually.

## Build from source

```bash
cd 01_workspace
swift build
swift test
```

Build and launch the application:

```bash
./script/build_and_run.sh
```

Create local ad-hoc ZIP and DMG preview packages without user data:

```bash
./script/build_and_run.sh --package
```

Formal releases use Developer ID and notarization credentials supplied through CI secrets and run from the tag workflow:

```bash
WEEKFLOW_DEVELOPER_ID="Developer ID Application: …" \
WEEKFLOW_NOTARY_PROFILE=weekflow-ci \
./script/build_and_run.sh --release
```
