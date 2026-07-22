import Foundation

enum DurationDisplay {
    /// A single, documented presentation rule. Storage and accumulation never
    /// round; minute-based statistics show completed whole minutes.
    static func minutes(for seconds: Int) -> Int {
        max(seconds, 0) / 60
    }
}
