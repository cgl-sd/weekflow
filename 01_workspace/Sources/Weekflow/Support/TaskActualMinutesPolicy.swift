import Foundation

enum TaskActualMinutesPolicy {
    static func resolved(manual: Int, live: Int, timerIsRunning: Bool) -> Int {
        timerIsRunning ? max(manual, live) : manual
    }
}
