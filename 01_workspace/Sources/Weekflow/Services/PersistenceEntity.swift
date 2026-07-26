import Foundation

/// Central registry of the `entityType` discriminator strings stored in the
/// persistence layer (Phase 3-3 fix). Keeping them in one place prevents the
/// typo → silent query-mismatch class of bugs that scattered string literals
/// invite.
///
/// - Important: these values are PERSISTED. They must never change without a
///   data migration, or existing records would stop matching their queries.
enum PersistenceEntity {
    static let goal = "goal"
    static let task = "task"
    static let taskAssignment = "taskAssignment"
    static let weeklyPlan = "weeklyPlan"
    static let channel = "channel"
    static let calendarEvent = "calendarEvent"
    static let dailyPlan = "dailyPlan"
    static let focusSession = "focusSession"
    static let dailyReview = "dailyReview"
    static let activeTimerSession = "activeTimerSession"
}

/// Central registry of the `undoState` strings on mutation transactions
/// (Phase 3-3 fix). Persisted — must not change without a migration.
enum PersistenceUndoState {
    /// Default: the transaction is available to be undone.
    static let available = "available"
    /// The transaction was committed and can no longer be undone.
    static let committed = "committed"
    /// The transaction has been undone.
    static let undone = "undone"
}
