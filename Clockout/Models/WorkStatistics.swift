import Foundation

/// A day without a target, e.g. vacation. Stored per job, see `Job.absences`.
enum AbsenceKind: String, Codable, CaseIterable, Identifiable {
    case vacation
    case sick
    case holiday

    var id: Self { self }

    var title: String {
        switch self {
        case .vacation: String(localized: "Vacation")
        case .sick: String(localized: "Sick")
        case .holiday: String(localized: "Holiday")
        }
    }

    var systemImage: String {
        switch self {
        case .vacation: "sun.max"
        case .sick: "cross.case"
        case .holiday: "flag"
        }
    }
}

struct Absence: Codable, Hashable {
    /// Start of the day.
    var day: Date
    var kindRaw: String

    init(day: Date, kind: AbsenceKind) {
        self.day = day
        self.kindRaw = kind.rawValue
    }

    var kind: AbsenceKind { AbsenceKind(rawValue: kindRaw) ?? .vacation }
}

/// The parts of the user settings that affect calculations.
struct WorkSettings: Equatable {
    /// Target per workday. A weekly target is spread evenly over the workdays.
    var dailyTarget: TimeInterval = 8 * 3600
    /// Calendar weekday numbers (1 = Sunday, 2 = Monday, ...).
    var workdays: Set<Int> = [2, 3, 4, 5, 6]
    var roundingMinutes = 1
    /// When set, workdays without any tracked time do not count against the balance
    /// (vacation, sick days, public holidays).
    var targetOnlyOnTrackedDays = true
    /// First day of the job. Days before it have no target.
    var startDate: Date?
    /// Days without a target, keyed by start of day.
    var absences: [Date: AbsenceKind] = [:]
    /// Public holidays have no target. `nil` when they are switched off.
    var holidayRegion: HolidayRegion?
    /// Holidays of the region that still count as normal days, e.g. a regional one the employer ignores.
    var ignoredHolidays: Set<HolidayKind> = []

    func absence(on day: Date, calendar: Calendar = .app) -> AbsenceKind? {
        absences[calendar.startOfDay(for: day)]
    }

    func holiday(on day: Date, calendar: Calendar = .app) -> Holiday? {
        guard let holidayRegion,
              let holiday = HolidayCalendar.holiday(on: day, region: holidayRegion, calendar: calendar),
              !ignoredHolidays.contains(holiday.kind)
        else { return nil }
        return holiday
    }

    func isWorkday(_ date: Date, calendar: Calendar = .app) -> Bool {
        workdays.contains(calendar.component(.weekday, from: date))
    }

    /// The target a day is planned with, regardless of what was tracked: 0 on days off.
    func plannedTarget(for day: Date, calendar: Calendar = .app) -> TimeInterval {
        let start = calendar.startOfDay(for: day)
        guard isWorkday(day, calendar: calendar) else { return 0 }
        if let startDate, start < calendar.startOfDay(for: startDate) { return 0 }
        if absences[start] != nil || holiday(on: start, calendar: calendar) != nil { return 0 }
        return dailyTarget
    }

    func target(for day: Date, worked: TimeInterval, now: Date, calendar: Calendar = .app) -> TimeInterval {
        guard calendar.startOfDay(for: day) <= calendar.startOfDay(for: now) else { return 0 }
        if targetOnlyOnTrackedDays && worked <= 0 { return 0 }
        return plannedTarget(for: day, calendar: calendar)
    }
}

struct DayStats: Identifiable {
    let day: Date
    let report: DayReport
    let target: TimeInterval
    let isWorkday: Bool
    let absence: AbsenceKind?
    let holiday: Holiday?

    var id: Date { day }
    var worked: TimeInterval { report.workedDuration }
    var balance: TimeInterval { worked - target }
}

struct PeriodSummary {
    let worked: TimeInterval
    let target: TimeInterval
    let trackedDays: Int
    /// Absence days that fall on workdays.
    let absenceDays: Int
    /// Public holidays on workdays that are not already absence days.
    let holidayDays: Int

    init(days: [DayStats]) {
        worked = days.reduce(0) { $0 + $1.worked }
        target = days.reduce(0) { $0 + $1.target }
        trackedDays = days.filter { !$0.report.isEmpty }.count
        absenceDays = days.filter { $0.isWorkday && $0.absence != nil }.count
        holidayDays = days.filter { $0.isWorkday && $0.absence == nil && $0.holiday != nil }.count
    }

    var balance: TimeInterval { worked - target }
    var averagePerTrackedDay: TimeInterval { trackedDays > 0 ? worked / Double(trackedDays) : 0 }
}

/// Starting point of the running balance: "+12:30 h as of 1 January".
struct BalanceCarryOver: Equatable {
    let balance: TimeInterval
    let since: Date
}

struct OverallBalance: Equatable {
    let balance: TimeInterval
    /// First day that is counted.
    let since: Date
    let carryOver: TimeInterval
}

enum WorkStatistics {
    /// Carry-over plus the balance of every day from its date (or from the start date or the first entry) up to today.
    static func overallBalance(
        intervals: [WorkInterval],
        settings: WorkSettings,
        carryOver: BalanceCarryOver?,
        now: Date,
        calendar: Calendar = .app
    ) -> OverallBalance? {
        let start: Date
        if let carryOver {
            start = calendar.startOfDay(for: carryOver.since)
        } else if let startDate = settings.startDate {
            start = calendar.startOfDay(for: startDate)
        } else if let first = intervals.map(\.start).min() {
            start = calendar.startOfDay(for: first)
        } else {
            return nil
        }

        let carried = carryOver?.balance ?? 0
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)), start < end else {
            return OverallBalance(balance: carried, since: start, carryOver: carried)
        }
        let counted = intervals.filter { $0.start >= start }
        let days = self.days(in: DateInterval(start: start, end: end), intervals: counted, settings: settings, now: now, calendar: calendar)
        return OverallBalance(balance: carried + PeriodSummary(days: days).balance, since: start, carryOver: carried)
    }

    /// One entry per calendar day in `interval`. Blocks belong to the day they started on.
    static func days(
        in interval: DateInterval,
        intervals: [WorkInterval],
        settings: WorkSettings,
        now: Date,
        calendar: Calendar = .app
    ) -> [DayStats] {
        let grouped = Dictionary(grouping: intervals) { calendar.startOfDay(for: $0.start) }
        var result: [DayStats] = []
        var day = calendar.startOfDay(for: interval.start)

        while day < interval.end {
            let report = DayReport(intervals: grouped[day] ?? [])
            result.append(DayStats(
                day: day,
                report: report,
                target: settings.target(for: day, worked: report.workedDuration, now: now, calendar: calendar),
                isWorkday: settings.isWorkday(day, calendar: calendar),
                absence: settings.absences[day],
                holiday: settings.holiday(on: day, calendar: calendar)
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    static func days(
        in interval: DateInterval,
        sessions: [WorkSession],
        settings: WorkSettings,
        now: Date,
        calendar: Calendar = .app
    ) -> [DayStats] {
        days(in: interval, intervals: sessions.map { $0.interval(now: now) }, settings: settings, now: now, calendar: calendar)
    }
}
