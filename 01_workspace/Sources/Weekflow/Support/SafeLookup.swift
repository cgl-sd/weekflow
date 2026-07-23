import Foundation

extension Dictionary {
    /// Builds a dictionary from key-value pairs, deterministically keeping the
    /// FIRST value when duplicate keys occur — instead of trapping the process
    /// like `init(uniqueKeysWithValues:)`.
    ///
    /// Phase 2-2 fix: ID-keyed lookups over persisted, imported, migrated, or
    /// in-memory data must never crash the app if a corrupted or legacy source
    /// contains duplicate IDs. For well-formed data (unique keys) the behavior is
    /// identical to `init(uniqueKeysWithValues:)` because the combining closure is
    /// never invoked, so this is a drop-in, behavior-preserving hardening.
    init(keepingFirst pairs: some Sequence<(Key, Value)>) {
        self.init(pairs, uniquingKeysWith: { first, _ in first })
    }
}
