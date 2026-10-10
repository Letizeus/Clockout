import Foundation
import SwiftData

enum JobColor: String, CaseIterable, Identifiable {
    case blue
    case purple
    case indigo
    case red
    case orange
    case yellow
    case green
    case teal
    case gray

    var id: Self { self }
}

/// An employer or client with its own entries and working time rules.
@Model
final class Job {
    /// Stable identifier stored on each `WorkSession`.
    var uuid: UUID = UUID()
    var name: String = ""
    var colorName: String = JobColor.blue.rawValue
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    var targetModeRaw: String = TargetMode.daily.rawValue
    var dailyTargetMinutes: Int = 480
    var weeklyTargetMinutes: Int = 2400
    /// Calendar weekday numbers (1 = Sunday, 2 = Monday, ...).
    var workdayList: [Int] = [2, 3, 4, 5, 6]
    var roundingMinutes: Int = 1
    var targetOnlyOnTrackedDays: Bool = true
    var breakFormatRaw: String = BreakFormat.clock.rawValue
    /// Square PNG shown instead of the colored initial, see `JobIconImage`.
    @Attribute(.externalStorage) var iconData: Data?
    /// Balance carried over from before `balanceCarryOverDate`, e.g. from last year. Negative for minus hours.
    var balanceCarryOverMinutes: Int = 0
    /// Days before this date are covered by the carry-over and no longer counted. `nil` means no carry-over.
    var balanceCarryOverDate: Date?
    /// First day of work. Days before it have no target. `nil` means no limit.
    var startDate: Date?
    /// Vacation, sick days and public holidays. At most one entry per day.
    var absences: [Absence] = []
    var holidaysEnabled: Bool = true
    /// `HolidayRegion.code`, e.g. "DE-BY". Empty until the location was detected or a region was chosen.
    var holidayRegionCode: String = ""
    /// `HolidayKind` raw values of holidays that count as normal days for this job.
    var ignoredHolidayList: [String] = []

    init(name: String, color: JobColor = .blue, sortIndex: Int = 0) {
        self.name = name
        self.colorName = color.rawValue
        self.sortIndex = sortIndex
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled") : trimmed
    }

    var color: JobColor {
        get { JobColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }

    var targetMode: TargetMode {
        get { TargetMode(rawValue: targetModeRaw) ?? .daily }
        set { targetModeRaw = newValue.rawValue }
    }

    var breakFormat: BreakFormat {
        get { BreakFormat(rawValue: breakFormatRaw) ?? .clock }
        set { breakFormatRaw = newValue.rawValue }
    }

    var workdays: Set<Int> {
        get { Set(workdayList) }
        set { workdayList = newValue.sorted() }
    }

    /// Target per workday. A weekly target is spread evenly over the workdays.
    var dailyTarget: TimeInterval {
        switch targetMode {
        case .daily:
            return TimeInterval(dailyTargetMinutes * 60)
        case .weekly:
            guard !workdayList.isEmpty else { return 0 }
            return TimeInterval(weeklyTargetMinutes * 60) / Double(workdayList.count)
        }
    }

    var weeklyTarget: TimeInterval { dailyTarget * Double(workdayList.count) }

    var rules: WorkSettings {
        WorkSettings(
            dailyTarget: dailyTarget,
            workdays: workdays,
            roundingMinutes: roundingMinutes,
            targetOnlyOnTrackedDays: targetOnlyOnTrackedDays,
            startDate: startDate,
            absences: Dictionary(absences.map { ($0.day, $0.kind) }, uniquingKeysWith: { _, last in last }),
            holidayRegion: holidaysEnabled ? holidayRegion : nil,
            ignoredHolidays: ignoredHolidays
        )
    }

    var holidayRegion: HolidayRegion? {
        get { HolidayRegion(code: holidayRegionCode) }
        set { holidayRegionCode = newValue?.code ?? "" }
    }

    var ignoredHolidays: Set<HolidayKind> {
        get { Set(ignoredHolidayList.compactMap(HolidayKind.init(rawValue:))) }
        set { ignoredHolidayList = newValue.map(\.rawValue).sorted() }
    }

    /// Absence first, then a public holiday: why this day has no target, if any.
    func dayOff(on day: Date) -> String? {
        if let absence = absence(on: day) { return absence.title }
        return rules.holiday(on: day)?.title
    }

    func absence(on day: Date) -> AbsenceKind? {
        let start = Calendar.app.startOfDay(for: day)
        return absences.last { $0.day == start }?.kind
    }

    /// Sets or clears the absence for each of the given days.
    func setAbsence(_ kind: AbsenceKind?, on days: [Date]) {
        let starts = Set(days.map { Calendar.app.startOfDay(for: $0) })
        var updated = absences.filter { !starts.contains($0.day) }
        if let kind {
            updated += starts.sorted().map { Absence(day: $0, kind: kind) }
        }
        absences = updated.sorted { $0.day < $1.day }
    }

    func isWorkday(_ date: Date) -> Bool { rules.isWorkday(date) }

    var carryOver: BalanceCarryOver? {
        balanceCarryOverDate.map { BalanceCarryOver(balance: TimeInterval(balanceCarryOverMinutes * 60), since: $0) }
    }

    /// Switches how the target is entered without changing the effective target.
    func changeTargetMode(to mode: TargetMode) {
        guard mode != targetMode else { return }
        switch mode {
        case .daily: dailyTargetMinutes = Int((dailyTarget / 60).rounded())
        case .weekly: weeklyTargetMinutes = Int((weeklyTarget / 60).rounded())
        }
        targetMode = mode
    }

    func copyRules(from other: Job) {
        targetModeRaw = other.targetModeRaw
        dailyTargetMinutes = other.dailyTargetMinutes
        weeklyTargetMinutes = other.weeklyTargetMinutes
        workdayList = other.workdayList
        roundingMinutes = other.roundingMinutes
        targetOnlyOnTrackedDays = other.targetOnlyOnTrackedDays
        breakFormatRaw = other.breakFormatRaw
        holidaysEnabled = other.holidaysEnabled
        holidayRegionCode = other.holidayRegionCode
        ignoredHolidayList = other.ignoredHolidayList
    }
}
