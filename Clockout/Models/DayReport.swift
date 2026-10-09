import Foundation

struct WorkInterval: Hashable {
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// The actual working time of one day: merged work blocks and the gaps between them.
struct DayReport: Equatable {
    let workIntervals: [WorkInterval]
    let breakIntervals: [WorkInterval]

    init(intervals: [WorkInterval]) {
        let sorted = intervals
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }

        // Overlapping blocks (e.g. after manual edits) must not be counted twice.
        var merged: [WorkInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }

        workIntervals = merged
        breakIntervals = zip(merged, merged.dropFirst()).map { WorkInterval(start: $0.end, end: $1.start) }
    }

    init(sessions: [WorkSession], now: Date) {
        self.init(intervals: sessions.map { $0.interval(now: now) })
    }

    var isEmpty: Bool { workIntervals.isEmpty }
    var firstStart: Date? { workIntervals.first?.start }
    var lastEnd: Date? { workIntervals.last?.end }

    var workedDuration: TimeInterval { workIntervals.reduce(0) { $0 + $1.duration } }
    var breakDuration: TimeInterval { breakIntervals.reduce(0) { $0 + $1.duration } }

    /// Time between the first start and the last end.
    var presenceDuration: TimeInterval {
        guard let firstStart, let lastEnd else { return 0 }
        return lastEnd.timeIntervalSince(firstStart)
    }
}

/// A single "from, to, break" line as required by a classic timesheet.
///
/// Several work blocks are condensed into one entry: the start is the first start,
/// the break is the sum of all gaps, and the end follows from start + work + break,
/// so the worked time always equals the tracked time.
struct TimesheetEntry: Equatable {
    let start: Date
    let end: Date
    let breakDuration: TimeInterval

    var workedDuration: TimeInterval { end.timeIntervalSince(start) - breakDuration }

    init(start: Date, end: Date, breakDuration: TimeInterval) {
        self.start = start
        self.end = end
        self.breakDuration = breakDuration
    }

    init?(report: DayReport, roundingMinutes: Int, calendar: Calendar = .app) {
        guard let firstStart = report.firstStart else { return nil }

        let step = TimeInterval(max(1, roundingMinutes) * 60)
        let dayStart = calendar.startOfDay(for: firstStart)
        let start = dayStart.addingTimeInterval(Self.round(firstStart.timeIntervalSince(dayStart), to: step))
        let worked = Self.round(report.workedDuration, to: step)
        let pause = Self.round(report.breakDuration, to: step)

        self.init(start: start, end: start.addingTimeInterval(worked + pause), breakDuration: pause)
    }

    static func round(_ value: TimeInterval, to step: TimeInterval) -> TimeInterval {
        (value / step).rounded() * step
    }
}
