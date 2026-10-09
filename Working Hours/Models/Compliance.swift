import Foundation

enum ComplianceIssue: Hashable {
    case insufficientBreak(worked: TimeInterval, required: TimeInterval, taken: TimeInterval)
    case exceedsDailyMaximum(worked: TimeInterval)
}

/// Checks based on the German Arbeitszeitgesetz (ArbZG, sections 3 and 4).
enum Compliance {
    /// Breaks shorter than this do not count towards the legal minimum.
    static let minimumBreakBlock: TimeInterval = 15 * 60
    static let dailyMaximum: TimeInterval = 10 * 3600

    static func requiredBreak(forWorked worked: TimeInterval) -> TimeInterval {
        if worked > 9 * 3600 { return 45 * 60 }
        if worked > 6 * 3600 { return 30 * 60 }
        return 0
    }

    static func qualifyingBreak(in report: DayReport) -> TimeInterval {
        report.breakIntervals
            .filter { $0.duration >= minimumBreakBlock }
            .reduce(0) { $0 + $1.duration }
    }

    static func issues(for report: DayReport) -> [ComplianceIssue] {
        let worked = report.workedDuration
        var issues: [ComplianceIssue] = []

        let required = requiredBreak(forWorked: worked)
        let taken = qualifyingBreak(in: report)
        if taken < required {
            issues.append(.insufficientBreak(worked: worked, required: required, taken: taken))
        }
        if worked > dailyMaximum {
            issues.append(.exceedsDailyMaximum(worked: worked))
        }
        return issues
    }
}
