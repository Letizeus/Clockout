import Foundation
import SwiftData

/// One uninterrupted block of work. Pausing ends the block, resuming starts a new one.
@Model
final class WorkSession {
    var start: Date
    /// `nil` while the timer is running.
    var end: Date?
    var note: String
    /// `Job.uuid` of the job this block belongs to. `nil` only for data from before jobs existed.
    var jobID: UUID?

    init(start: Date, end: Date? = nil, note: String = "", jobID: UUID? = nil) {
        self.start = start
        self.end = end
        self.note = note
        self.jobID = jobID
    }

    var isRunning: Bool { end == nil }

    func interval(now: Date) -> WorkInterval {
        WorkInterval(start: start, end: max(start, end ?? now))
    }

    func duration(now: Date) -> TimeInterval {
        interval(now: now).duration
    }
}
