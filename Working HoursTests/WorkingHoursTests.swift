import Foundation
import Testing
@testable import Working_Hours

@MainActor
struct DayReportTests {
    @Test func mergesOverlappingBlocksAndComputesBreaks() {
        let report = DayReport(intervals: [
            interval(13, 0, to: 17, 0),
            interval(8, 0, to: 12, 0),
            interval(11, 30, to: 12, 30),
        ])

        #expect(report.workIntervals == [interval(8, 0, to: 12, 30), interval(13, 0, to: 17, 0)])
        #expect(report.breakIntervals == [interval(12, 30, to: 13, 0)])
        #expect(report.workedDuration == hours(8.5))
        #expect(report.breakDuration == minutes(30))
        #expect(report.presenceDuration == hours(9))
    }

    @Test func ignoresEmptyBlocks() {
        let report = DayReport(intervals: [interval(9, 0, to: 9, 0)])
        #expect(report.isEmpty)
        #expect(TimesheetEntry(report: report, roundingMinutes: 1) == nil)
    }
}

@MainActor
struct TimesheetEntryTests {
    @Test func condensesSeveralBlocksIntoOneConsistentLine() throws {
        let report = DayReport(intervals: [
            interval(8, 3, 20, to: 10, 0),
            interval(10, 10, to: 12, 0),
            interval(12, 45, to: 17, 2, 40),
        ])
        let entry = try #require(TimesheetEntry(report: report, roundingMinutes: 1))

        #expect(entry.start == date(8, 3))
        #expect(entry.breakDuration == minutes(55))
        #expect(entry.workedDuration == hours(8) + minutes(4))
        #expect(entry.end == date(17, 2))
        #expect(entry.end.timeIntervalSince(entry.start) - entry.breakDuration == entry.workedDuration)
    }

    @Test func roundsToQuarterHours() throws {
        let report = DayReport(intervals: [
            interval(8, 7, to: 12, 0),
            interval(12, 31, to: 16, 52),
        ])
        let entry = try #require(TimesheetEntry(report: report, roundingMinutes: 15))

        #expect(entry.start == date(8, 0))
        #expect(entry.breakDuration == minutes(30))
        #expect(entry.workedDuration == hours(8.25))
        #expect(entry.end == date(16, 45))
    }

    @Test func singleBlockHasNoBreak() throws {
        let entry = try #require(TimesheetEntry(report: DayReport(intervals: [interval(9, 0, to: 13, 30)]), roundingMinutes: 1))
        #expect(entry.start == date(9, 0))
        #expect(entry.end == date(13, 30))
        #expect(entry.breakDuration == 0)
    }
}

@MainActor
struct ComplianceTests {
    @Test func requiredBreakFollowsArbZG() {
        #expect(Compliance.requiredBreak(forWorked: hours(6)) == 0)
        #expect(Compliance.requiredBreak(forWorked: hours(6) + 60) == minutes(30))
        #expect(Compliance.requiredBreak(forWorked: hours(9) + 60) == minutes(45))
    }

    @Test func shortInterruptionsDoNotCount() {
        let report = DayReport(intervals: [
            interval(8, 0, to: 11, 0),
            interval(11, 10, to: 13, 0),
            interval(13, 10, to: 15, 20),
        ])
        #expect(report.workedDuration == hours(7))
        #expect(Compliance.issues(for: report) == [.insufficientBreak(worked: hours(7), required: minutes(30), taken: 0)])
    }

    @Test func sufficientBreakHasNoIssues() {
        let report = DayReport(intervals: [interval(8, 0, to: 12, 0), interval(12, 30, to: 16, 0)])
        #expect(Compliance.issues(for: report).isEmpty)
    }

    @Test func flagsMoreThanTenHours() {
        let report = DayReport(intervals: [interval(6, 0, to: 12, 0), interval(12, 45, to: 17, 45)])
        #expect(Compliance.issues(for: report) == [.exceedsDailyMaximum(worked: hours(11))])
    }
}

@MainActor
struct WorkStatisticsTests {
    // Monday 5 October 2026 to Sunday 11 October 2026.
    private var week: DateInterval {
        DateInterval(start: date(0, 0, day: 5), end: date(0, 0, day: 12))
    }

    private var intervals: [WorkInterval] {
        [
            interval(8, 0, to: 12, 0, day: 5),
            interval(12, 30, to: 17, 0, day: 5),
            interval(10, 0, to: 12, 0, day: 10),
        ]
    }

    @Test func targetOnlyOnTrackedDays() {
        let days = WorkStatistics.days(
            in: week,
            intervals: intervals,
            settings: WorkSettings(),
            now: date(20, 0, day: 11)
        )
        let summary = PeriodSummary(days: days)

        #expect(days.count == 7)
        #expect(summary.worked == hours(10.5))
        #expect(summary.target == hours(8))
        #expect(summary.balance == hours(2.5))
        #expect(summary.trackedDays == 2)
    }

    @Test func targetOnEveryWorkdayUpToToday() {
        var settings = WorkSettings()
        settings.targetOnlyOnTrackedDays = false
        let days = WorkStatistics.days(in: week, intervals: intervals, settings: settings, now: date(20, 0, day: 7))

        // Monday to Wednesday count, Thursday and Friday are still in the future.
        #expect(PeriodSummary(days: days).target == hours(24))
    }
}

@MainActor
struct CarryOverTests {
    // Monday 5 to Thursday 8 October 2026, 8 h target per workday.
    private let intervals = [
        interval(8, 0, to: 17, 0, day: 5),
        interval(8, 0, to: 18, 0, day: 6),
        interval(8, 0, to: 15, 0, day: 7),
    ]

    @Test func withoutCarryOverCountsFromFirstEntry() throws {
        let overall = try #require(WorkStatistics.overallBalance(intervals: intervals, settings: WorkSettings(), carryOver: nil, now: date(20, 0)))
        // +1 h, +2 h, -1 h; Thursday has no entry and does not count (target only on tracked days).
        #expect(overall.balance == 2 * 3600)
        #expect(overall.since == date(0, 0, day: 5))
        #expect(overall.carryOver == 0)
    }

    @Test func carryOverReplacesEverythingBeforeItsDate() throws {
        let carryOver = BalanceCarryOver(balance: -5.5 * 3600, since: date(0, 0, day: 6))
        let overall = try #require(WorkStatistics.overallBalance(intervals: intervals, settings: WorkSettings(), carryOver: carryOver, now: date(20, 0)))
        // Monday is covered by the carry-over: -5:30 + 2 h - 1 h.
        #expect(overall.balance == -4.5 * 3600)
        #expect(overall.since == date(0, 0, day: 6))
    }

    @Test func carryOverWorksWithoutEntries() throws {
        let carryOver = BalanceCarryOver(balance: 12.5 * 3600, since: date(0, 0, day: 8))
        let overall = try #require(WorkStatistics.overallBalance(intervals: [], settings: WorkSettings(), carryOver: carryOver, now: date(9, 0)))
        #expect(overall.balance == 12.5 * 3600)
        #expect(WorkStatistics.overallBalance(intervals: [], settings: WorkSettings(), carryOver: nil, now: date(9, 0)) == nil)
    }

    @Test func jobExposesItsCarryOver() {
        let job = Job(name: "Werkstudent")
        #expect(job.carryOver == nil)
        job.balanceCarryOverMinutes = -90
        job.balanceCarryOverDate = date(0, 0, day: 1)
        #expect(job.carryOver == BalanceCarryOver(balance: -5400, since: date(0, 0, day: 1)))
    }
}

@MainActor
struct StartDateAndAbsenceTests {
    // Monday 5 to Friday 9 October 2026, 8 h target on every workday.
    private var settings: WorkSettings {
        var settings = WorkSettings()
        settings.targetOnlyOnTrackedDays = false
        return settings
    }

    private var week: DateInterval { DateInterval(start: date(0, 0, day: 5), end: date(0, 0, day: 10)) }

    @Test func noTargetBeforeStartDate() {
        var settings = settings
        settings.startDate = date(0, 0, day: 7)
        let days = WorkStatistics.days(in: week, intervals: [], settings: settings, now: date(20, 0, day: 9))
        // Only Wednesday to Friday count.
        #expect(PeriodSummary(days: days).target == 3 * 8 * 3600)
    }

    @Test func overallBalanceStartsAtStartDate() throws {
        var settings = settings
        settings.startDate = date(0, 0, day: 8)
        let overall = try #require(WorkStatistics.overallBalance(
            intervals: [interval(8, 0, to: 17, 0, day: 9)], settings: settings, carryOver: nil, now: date(20, 0, day: 9)
        ))
        // Thursday without entry -8 h, Friday +1 h.
        #expect(overall.balance == -7 * 3600)
        #expect(overall.since == date(0, 0, day: 8))
    }

    @Test func absenceDaysHaveNoTarget() {
        var settings = settings
        settings.absences = [date(0, 0, day: 6): .vacation, date(0, 0, day: 7): .sick]
        let days = WorkStatistics.days(in: week, intervals: [interval(8, 0, to: 10, 0, day: 6)], settings: settings, now: date(20, 0, day: 9))
        let summary = PeriodSummary(days: days)
        #expect(summary.target == 3 * 8 * 3600)
        #expect(summary.absenceDays == 2)
        // Work on a vacation day still counts.
        #expect(summary.worked == 2 * 3600)
    }

    @Test func jobStoresOneAbsencePerDay() {
        let job = Job(name: "Test")
        job.setAbsence(.vacation, on: [date(10, 0, day: 5), date(0, 0, day: 6)])
        job.setAbsence(.sick, on: [date(15, 0, day: 6)])
        #expect(job.absences.count == 2)
        #expect(job.absence(on: date(12, 0, day: 6)) == .sick)
        #expect(job.rules.absences[date(0, 0, day: 5)] == .vacation)
        job.setAbsence(nil, on: [date(0, 0, day: 5)])
        #expect(job.absence(on: date(0, 0, day: 5)) == nil)
    }

    @Test func exportListsAbsenceDays() {
        var settings = settings
        settings.absences = [date(0, 0, day: 6): .vacation]
        let days = WorkStatistics.days(in: week, intervals: [], settings: settings, now: date(20, 0, day: 9))
        let lines = CSVExporter.makeCSV(days: days, roundingMinutes: 1, includeEmptyWorkdays: false)
            .split(separator: "\r\n")
        #expect(lines.count == 2)
        #expect(lines[1].hasPrefix("06.10.2026;"))
        #expect(lines[1].hasSuffix(";Urlaub"))
    }
}

@MainActor
struct HolidayTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.app.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func computesEasterSunday() {
        #expect(HolidayCalendar.easterSunday(year: 2000) == day(2000, 4, 23))
        #expect(HolidayCalendar.easterSunday(year: 2024) == day(2024, 3, 31))
        #expect(HolidayCalendar.easterSunday(year: 2025) == day(2025, 4, 20))
        #expect(HolidayCalendar.easterSunday(year: 2026) == day(2026, 4, 5))
        #expect(HolidayCalendar.easterSunday(year: 2027) == day(2027, 3, 28))
    }

    @Test func bavariaHasThirteenHolidaysIn2026() {
        let holidays = HolidayCalendar.holidays(in: 2026, region: HolidayRegion(country: .germany, state: .bavaria))
        #expect(holidays.count == 13)
        #expect(holidays[day(2026, 6, 4)]?.title == "Fronleichnam")
        #expect(holidays[day(2026, 5, 14)]?.title == "Christi Himmelfahrt")
        #expect(holidays[day(2026, 10, 31)] == nil)
    }

    @Test func statesDiffer() {
        let saxony = HolidayCalendar.holidays(in: 2026, region: HolidayRegion(country: .germany, state: .saxony))
        #expect(saxony[day(2026, 11, 18)]?.title == "Buß- und Bettag")
        #expect(saxony[day(2026, 10, 31)]?.title == "Reformationstag")
        let nationwide = HolidayCalendar.holidays(in: 2026, region: HolidayRegion(country: .germany))
        #expect(nationwide.count == 9)
        let austria = HolidayCalendar.holidays(in: 2026, region: HolidayRegion(country: .austria))
        #expect(austria[day(2026, 10, 26)]?.title == "Nationalfeiertag")
        #expect(austria[day(2026, 4, 3)] == nil)
    }

    @Test func readsRegionsFromCodesAndGeocoderNames() {
        #expect(HolidayRegion(code: "DE-BY") == HolidayRegion(country: .germany, state: .bavaria))
        #expect(HolidayRegion(code: "AT")?.code == "AT")
        #expect(HolidayRegion(code: "XX") == nil)
        #expect(GermanState(name: "Bavaria") == .bavaria)
        #expect(GermanState(name: "North Rhine-Westphalia") == .northRhineWestphalia)
        #expect(GermanState(name: "Thüringen") == .thuringia)
        #expect(GermanState(name: "Nowhere") == nil)
    }

    @Test func holidaysHaveNoTargetButWorkStillCounts() {
        var settings = WorkSettings()
        settings.targetOnlyOnTrackedDays = false
        settings.holidayRegion = HolidayRegion(country: .germany, state: .bavaria)
        // Week of Ascension 2026: Monday 11 to Friday 15 May, Thursday is a holiday.
        let week = DateInterval(start: day(2026, 5, 11), end: day(2026, 5, 16))
        let worked = WorkInterval(start: day(2026, 5, 14).addingTimeInterval(9 * 3600), end: day(2026, 5, 14).addingTimeInterval(13 * 3600))
        let summary = PeriodSummary(days: WorkStatistics.days(in: week, intervals: [worked], settings: settings, now: day(2026, 5, 20)))
        #expect(summary.target == 4 * 8 * 3600)
        #expect(summary.worked == 4 * 3600)
        #expect(summary.holidayDays == 1)

        settings.ignoredHolidays = [.ascension]
        let ignoring = PeriodSummary(days: WorkStatistics.days(in: week, intervals: [worked], settings: settings, now: day(2026, 5, 20)))
        #expect(ignoring.target == 5 * 8 * 3600)
    }

    @Test func jobExposesItsHolidaySettings() {
        let job = Job(name: "Test")
        #expect(job.rules.holidayRegion == nil)
        job.holidayRegion = HolidayRegion(country: .germany, state: .saxony)
        #expect(job.rules.holidayRegion?.state == .saxony)
        #expect(job.dayOff(on: day(2026, 11, 18)) == "Buß- und Bettag")
        job.holidaysEnabled = false
        #expect(job.rules.holidayRegion == nil)
        job.holidaysEnabled = true
        job.setAbsence(.vacation, on: [day(2026, 11, 18)])
        #expect(job.dayOff(on: day(2026, 11, 18)) == "Urlaub")
    }
}

@MainActor
struct FormattingAndExportTests {
    @Test func formatsDurations() {
        #expect((hours(7) + minutes(5)).clock == "7:05")
        #expect((hours(7) + minutes(5)).paddedClock == "07:05")
        #expect((-minutes(90)).signedClock == "-1:30")
        #expect(minutes(15).signedClock == "+0:15")
        #expect(TimeInterval(0).signedClock == "0:00")
        #expect((hours(1) + 62).stopwatch == "1:01:02")
        #expect(hours(7.75).decimalHours == "7,75")
    }

    @Test func exportsOneLinePerDay() {
        let days = WorkStatistics.days(
            in: DateInterval(start: date(0, 0), end: date(0, 0, day: 9)),
            intervals: [interval(8, 0, to: 12, 0), interval(12, 30, to: 16, 30)],
            settings: WorkSettings(),
            now: date(18, 0)
        )
        let csv = CSVExporter.makeCSV(days: days, roundingMinutes: 1, includeEmptyWorkdays: false)
        let lines = csv.split(separator: "\r\n").map(String.init)

        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Datum;Wochentag;Beginn;Ende;Pause;Arbeitszeit"))
        #expect(lines[1] == "08.10.2026;Donnerstag;08:00;16:30;00:30;08:00;8,00;08:00;0:00;08:00-12:00 / 12:30-16:30;")
    }
}

// MARK: Helpers

private func date(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 8) -> Date {
    Calendar.app.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
}

private func interval(_ h1: Int, _ m1: Int, _ s1: Int = 0, to h2: Int, _ m2: Int, _ s2: Int = 0, day: Int = 8) -> WorkInterval {
    WorkInterval(start: date(h1, m1, s1, day: day), end: date(h2, m2, s2, day: day))
}

private func hours(_ value: Double) -> TimeInterval { value * 3600 }
private func minutes(_ value: Double) -> TimeInterval { value * 60 }
