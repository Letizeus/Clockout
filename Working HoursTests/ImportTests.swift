import Foundation
import SwiftData
import Testing
@testable import Working_Hours

@MainActor
struct CSVReaderTests {
    @Test func detectsDelimiterAndHandlesQuotes() {
        let csv = "\u{FEFF}Datum;Beginn;Ende;Notiz\r\n08.10.2026;08:00;12:00;\"Meeting; mit \"\"Kunde\"\"\"\r\n\r\n"
        let rows = CSVReader.read(data: Data(csv.utf8))

        #expect(rows.count == 2)
        #expect(rows[0].map(\.text) == ["Datum", "Beginn", "Ende", "Notiz"])
        #expect(rows[1][3] == .text("Meeting; mit \"Kunde\""))
    }

    @Test func detectsCommaAndTab() {
        #expect(CSVReader.detectDelimiter("Date,Start,End\n2026-10-08,8:00,16:00") == ",")
        #expect(CSVReader.detectDelimiter("Datum\tVon\tBis\n08.10.2026\t8:00\t16:00") == "\t")
    }
}

@MainActor
struct TimesheetImporterTests {
    @Test func importsTypicalGermanTimesheetAndPlacesBreakInTheMiddle() throws {
        let rows = CSVReader.read(data: Data("Datum;Kommen;Gehen;Pause;Bemerkung\n08.10.2026;08:00;16:30;0:30;Büro\n".utf8))
        let mapping = TimesheetImporter.detectMapping(rows: rows)

        #expect(mapping.headerRow == 0)
        #expect(mapping.columns == [.date: 0, .start: 1, .end: 2, .pause: 3, .note: 4])

        let imported = TimesheetImporter.parse(rows: rows, mapping: mapping)
        let row = try #require(imported.first)
        #expect(row.error == nil)
        #expect(row.note == "Büro")
        #expect(row.blocks == [interval(8, 0, to: 12, 0), interval(12, 30, to: 16, 30)])
        #expect(row.worked == 8 * 3600)
    }

    @Test func roundTripsOwnExportExactly() throws {
        let original = [interval(8, 3, to: 10, 0), interval(10, 10, to: 12, 0), interval(12, 45, to: 17, 2)]
        let days = WorkStatistics.days(
            in: DateInterval(start: date(0, 0), end: date(0, 0, day: 9)),
            intervals: original,
            settings: WorkSettings(),
            now: date(20, 0)
        )
        let csv = CSVExporter.makeCSV(days: days, roundingMinutes: 1, includeEmptyWorkdays: false)

        let rows = CSVReader.read(data: Data(("\u{FEFF}" + csv).utf8))
        let mapping = TimesheetImporter.detectMapping(rows: rows)
        #expect(mapping.columns[.blocks] == 9)

        let imported = try #require(TimesheetImporter.parse(rows: rows, mapping: mapping).first)
        #expect(imported.blocks == original)
    }

    @Test func readsExcelFile() throws {
        let data = try #require(Data(base64Encoded: xlsxFixture, options: .ignoreUnknownCharacters))
        let source = try ImportSource.load(data: data, fileName: "Stunden.xlsx")

        #expect(source.isExcel)
        #expect(source.sheets.map(\.name) == ["Oktober", "Notizen"])

        let rows = source.sheets[0].rows
        #expect(rows[0].map(\.text) == ["Datum", "Kommen", "Gehen", "Pause", "Tätigkeit"])

        let mapping = TimesheetImporter.detectMapping(rows: rows)
        let imported = TimesheetImporter.parse(rows: rows, mapping: mapping)
        #expect(imported.count == 2)
        #expect(imported[0].blocks == [interval(8, 0, to: 12, 0), interval(12, 30, to: 16, 30)])
        #expect(imported[0].note == "Büro")
        #expect(imported[1].blocks == [interval(7, 45, to: 12, 0, day: 9)])
    }

    @Test func readsTimesheetWithUnlabeledDateColumn() throws {
        let data = try #require(Data(base64Encoded: universityTimesheetFixture, options: .ignoreUnknownCharacters))
        let rows = try ImportSource.load(data: data, fileName: "Stundennachweis.xlsx").sheets[0].rows
        let mapping = TimesheetImporter.detectMapping(rows: rows)

        #expect(mapping.headerRow == 0)
        #expect(mapping.columns == [.date: 2, .start: 3, .end: 4, .pause: 5, .note: 14])

        let imported = TimesheetImporter.parse(rows: rows, mapping: mapping)
        #expect(imported.allSatisfy { $0.isValid })
        #expect(imported.map(\.id) == [3, 5, 6])

        let january = { (day: Int, h1: Int, m1: Int, h2: Int, m2: Int) in
            WorkInterval(
                start: Calendar.app.date(from: DateComponents(year: 2026, month: 1, day: day, hour: h1, minute: m1))!,
                end: Calendar.app.date(from: DateComponents(year: 2026, month: 1, day: day, hour: h2, minute: m2))!
            )
        }
        #expect(imported[0].blocks == [january(2, 13, 20, 14, 0)])
        // 10:00 to 18:00 with 3:45 break, and 6:00 to 21:00 with a 4:30 break (an Excel time above 4 hours).
        #expect(imported[1].worked == 4.25 * 3600)
        #expect(imported[1].note == "Projekt A")
        #expect(imported[2].worked == 10.5 * 3600)
    }

    @Test func guessesColumnsWithoutHeader() {
        let rows = CSVReader.read(data: Data("08.10.2026;08:00;16:00;00:45\n09.10.2026;09:00;17:00;00:30\n".utf8))
        let mapping = TimesheetImporter.detectMapping(rows: rows)

        #expect(mapping.headerRow == nil)
        #expect(mapping.columns == [.date: 0, .start: 1, .end: 2, .pause: 3])
    }

    @Test func parsesTimesAndBreaks() {
        #expect(TimesheetImporter.parseTime(.text("8:05")) == 485)
        #expect(TimesheetImporter.parseTime(.text("16.30")) == 990)
        #expect(TimesheetImporter.parseTime(.text("4:30 PM")) == 990)
        #expect(TimesheetImporter.parseTime(.text("1630")) == 990)
        #expect(TimesheetImporter.parseTime(.text("8 Uhr")) == 480)
        #expect(TimesheetImporter.parseTime(.text("08.10.2026 07:15")) == 435)
        #expect(TimesheetImporter.parseTime(.number(0.75)) == 1080)
        #expect(TimesheetImporter.parseTime(.text("Summe")) == nil)

        #expect(TimesheetImporter.parseDuration(.text("30"), unit: .automatic) == 30)
        #expect(TimesheetImporter.parseDuration(.text("0,5"), unit: .automatic) == 30)
        #expect(TimesheetImporter.parseDuration(.text("00:45"), unit: .automatic) == 45)
        #expect(TimesheetImporter.parseDuration(.text("45 min"), unit: .automatic) == 45)
        #expect(TimesheetImporter.parseDuration(.number(0.0208333), unit: .automatic) == 30)
        #expect(TimesheetImporter.parseDuration(.number(0.5), unit: .automatic) == 30)
        #expect(TimesheetImporter.parseDuration(.number(1), unit: .decimalHours) == 60)
        #expect(TimesheetImporter.parseDuration(.empty, unit: .automatic) == 0)
    }

    @Test func handlesNightShiftsAndBadRows() {
        let rows = CSVReader.read(data: Data("Datum;Beginn;Ende;Pause\n08.10.2026;22:00;06:00;0:30\nSumme;;;\n09.10.2026;08:00;;\n10.10.2026;08:00;09:00;2:00\n".utf8))
        let imported = TimesheetImporter.parse(rows: rows, mapping: TimesheetImporter.detectMapping(rows: rows))

        #expect(imported.count == 3)
        #expect(imported[0].worked == 7.5 * 3600)
        #expect(imported[0].blocks.last?.end == date(6, 0, day: 9))
        #expect(imported[1].error == "Ende fehlt")
        #expect(imported[2].error == "Pause ist länger als die Anwesenheit")
    }
}

@MainActor
struct ImportApplyTests {
    private func makeTracker() throws -> (TimeTracker, ModelContainer) {
        let container = try ModelContainer(for: WorkSession.self, Job.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let defaults = UserDefaults(suiteName: "import-apply-tests")!
        defaults.removePersistentDomain(forName: "import-apply-tests")
        let jobs = JobStore(context: container.mainContext, defaults: defaults)
        let tracker = TimeTracker(context: container.mainContext, settings: AppSettings(defaults: defaults), jobs: jobs, defaults: defaults)
        container.mainContext.insert(WorkSession(start: date(9, 0), end: date(10, 0), note: "vorhanden", jobID: jobs.currentJob.uuid))
        return (tracker, container)
    }

    private var rows: [ImportedRow] {
        [
            ImportedRow(id: 2, day: date(0, 0), blocks: [interval(8, 0, to: 12, 0)], note: "", error: nil),
            ImportedRow(id: 3, day: date(0, 0, day: 9), blocks: [interval(8, 0, to: 16, 0, day: 9)], note: "", error: nil),
            ImportedRow(id: 4, day: nil, blocks: [], note: "", error: "Datum fehlt"),
        ]
    }

    @Test(arguments: [
        (ImportConflictStrategy.skipExistingDays, 1, 2),
        (ImportConflictStrategy.replaceExistingDays, 2, 2),
        (ImportConflictStrategy.add, 2, 3),
    ])
    func appliesConflictStrategy(strategy: ImportConflictStrategy, importedDays: Int, totalSessions: Int) throws {
        let (tracker, container) = try makeTracker()
        let result = tracker.importRows(rows, into: tracker.jobs.currentJob, strategy: strategy)

        #expect(result.importedDays == importedDays)
        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>())
        #expect(sessions.count == totalSessions)
        if strategy == .replaceExistingDays {
            #expect(!sessions.contains { $0.note == "vorhanden" })
        }
    }
}

// MARK: Helpers

/// Files with nonsense or hostile values must be rejected, not crash the app.
@MainActor
struct ImportHardeningTests {
    @Test func rejectsBreaksThatAreNoBreak() {
        #expect(TimesheetImporter.parseDuration(.text("99999999999999999999"), unit: .automatic) == nil)
        #expect(TimesheetImporter.parseDuration(.text("999999999999999999:00"), unit: .automatic) == nil)
        #expect(TimesheetImporter.parseDuration(.number(1e300), unit: .clock) == nil)
        #expect(TimesheetImporter.parseDuration(.number(.infinity), unit: .automatic) == nil)
        #expect(TimesheetImporter.parseDuration(.number(.nan), unit: .minutes) == nil)
        #expect(TimesheetImporter.parseDuration(.number(-5), unit: .minutes) == nil)
        #expect(TimesheetImporter.parseDuration(.text("25 h"), unit: .automatic) == nil)
    }

    @Test func stillReadsNormalBreaks() {
        #expect(TimesheetImporter.parseDuration(.number(30), unit: .automatic) == 30)
        #expect(TimesheetImporter.parseDuration(.text("0:30"), unit: .automatic) == 30)
        #expect(TimesheetImporter.parseDuration(.number(0.5 / 24), unit: .clock) == 30)
        #expect(TimesheetImporter.parseDuration(.text("24:00"), unit: .automatic) == 24 * 60)
    }

    @Test func rejectsTimesThatAreNotFinite() {
        #expect(TimesheetImporter.parseTime(.number(.infinity)) == nil)
        #expect(TimesheetImporter.parseTime(.number(.nan)) == nil)
        #expect(TimesheetImporter.parseTime(.number(0.5)) == 12 * 60)
    }

    @Test func ignoresRowsOutsideTheValidRange() throws {
        let sheets = try XLSXReader.read(data: try #require(Data(base64Encoded: HardeningFixtures.rowZero)))
        #expect(sheets.first?.rows.isEmpty == true)
    }

    @Test func survivesOverlongColumnReferences() throws {
        let sheets = try XLSXReader.read(data: try #require(Data(base64Encoded: HardeningFixtures.longColumn)))
        #expect(sheets.first?.rows.count == 1)
    }

    @Test func refusesZipEntriesThatClaimToBeHuge() throws {
        let data = try #require(Data(base64Encoded: HardeningFixtures.declaresHugeEntry))
        #expect(throws: ImportError.tooLarge) { try XLSXReader.read(data: data) }
    }

    @Test func refusesFilesAboveTheSizeLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).csv")
        try Data(count: ImportSource.maximumFileSize + 1).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ImportError.tooLarge) { try ImportSource.load(from: url) }
    }
}

/// Minimal workbooks with one crafted detail each.
private enum HardeningFixtures {
    /// A row numbered 0, which made the row index negative.
    static let rowZero = "UEsDBBQAAAAAAK4NSV17xzj4WwAAAFsAAAAPAAAAeGwvd29ya2Jvb2sueG1sPHdvcmtib29rIHhtbG5zOnI9InIiPjxzaGVldHM+PHNoZWV0IG5hbWU9IlMiIHNoZWV0SWQ9IjEiIHI6aWQ9InJJZDEiLz48L3NoZWV0cz48L3dvcmtib29rPlBLAwQUAAAAAACuDUld1MStWVcAAABXAAAAGgAAAHhsL19yZWxzL3dvcmtib29rLnhtbC5yZWxzPFJlbGF0aW9uc2hpcHM+PFJlbGF0aW9uc2hpcCBJZD0icklkMSIgVGFyZ2V0PSJ3b3Jrc2hlZXRzL3NoZWV0MS54bWwiLz48L1JlbGF0aW9uc2hpcHM+UEsDBBQAAAAAAK4NSV1ixtFMZQAAAGUAAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sPHdvcmtzaGVldD48c2hlZXREYXRhPjxyb3cgcj0iMCI+PGMgdD0iaW5saW5lU3RyIj48aXM+PHQ+eDwvdD48L2lzPjwvYz48L3Jvdz48L3NoZWV0RGF0YT48L3dvcmtzaGVldD5QSwECFAMUAAAAAACuDUlde8c4+FsAAABbAAAADwAAAAAAAAAAAAAAgAEAAAAAeGwvd29ya2Jvb2sueG1sUEsBAhQDFAAAAAAArg1JXdTErVlXAAAAVwAAABoAAAAAAAAAAAAAAIABiAAAAHhsL19yZWxzL3dvcmtib29rLnhtbC5yZWxzUEsBAhQDFAAAAAAArg1JXWLG0UxlAAAAZQAAABgAAAAAAAAAAAAAAIABFwEAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbFBLBQYAAAAAAwADAMsAAACyAQAAAAA="
    /// A 20 letter column reference, which overflowed the column index.
    static let longColumn = "UEsDBBQAAAAAAK4NSV17xzj4WwAAAFsAAAAPAAAAeGwvd29ya2Jvb2sueG1sPHdvcmtib29rIHhtbG5zOnI9InIiPjxzaGVldHM+PHNoZWV0IG5hbWU9IlMiIHNoZWV0SWQ9IjEiIHI6aWQ9InJJZDEiLz48L3NoZWV0cz48L3dvcmtib29rPlBLAwQUAAAAAACuDUld1MStWVcAAABXAAAAGgAAAHhsL19yZWxzL3dvcmtib29rLnhtbC5yZWxzPFJlbGF0aW9uc2hpcHM+PFJlbGF0aW9uc2hpcCBJZD0icklkMSIgVGFyZ2V0PSJ3b3Jrc2hlZXRzL3NoZWV0MS54bWwiLz48L1JlbGF0aW9uc2hpcHM+UEsDBBQAAAAAAK4NSV2UsL5KfwAAAH8AAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sPHdvcmtzaGVldD48c2hlZXREYXRhPjxyb3cgcj0iMSI+PGMgcj0iQUFBQUFBQUFBQUFBQUFBQUFBQUExIiB0PSJpbmxpbmVTdHIiPjxpcz48dD54PC90PjwvaXM+PC9jPjwvcm93Pjwvc2hlZXREYXRhPjwvd29ya3NoZWV0PlBLAQIUAxQAAAAAAK4NSV17xzj4WwAAAFsAAAAPAAAAAAAAAAAAAACAAQAAAAB4bC93b3JrYm9vay54bWxQSwECFAMUAAAAAACuDUld1MStWVcAAABXAAAAGgAAAAAAAAAAAAAAgAGIAAAAeGwvX3JlbHMvd29ya2Jvb2sueG1sLnJlbHNQSwECFAMUAAAAAACuDUldlLC+Sn8AAAB/AAAAGAAAAAAAAAAAAAAAgAEXAQAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sUEsFBgAAAAADAAMAywAAAMwBAAAAAA=="
    /// The sheet entry declares an uncompressed size of almost 4 GB.
    static let declaresHugeEntry = "UEsDBBQAAAAAAK4NSV17xzj4WwAAAFsAAAAPAAAAeGwvd29ya2Jvb2sueG1sPHdvcmtib29rIHhtbG5zOnI9InIiPjxzaGVldHM+PHNoZWV0IG5hbWU9IlMiIHNoZWV0SWQ9IjEiIHI6aWQ9InJJZDEiLz48L3NoZWV0cz48L3dvcmtib29rPlBLAwQUAAAAAACuDUld1MStWVcAAABXAAAAGgAAAHhsL19yZWxzL3dvcmtib29rLnhtbC5yZWxzPFJlbGF0aW9uc2hpcHM+PFJlbGF0aW9uc2hpcCBJZD0icklkMSIgVGFyZ2V0PSJ3b3Jrc2hlZXRzL3NoZWV0MS54bWwiLz48L1JlbGF0aW9uc2hpcHM+UEsDBBQAAAAAAK4NSV3Vl0oKbAAAAGwAAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sPHdvcmtzaGVldD48c2hlZXREYXRhPjxyb3cgcj0iMSI+PGMgcj0iQTEiIHQ9ImlubGluZVN0ciI+PGlzPjx0Png8L3Q+PC9pcz48L2M+PC9yb3c+PC9zaGVldERhdGE+PC93b3Jrc2hlZXQ+UEsBAhQDFAAAAAAArg1JXXvHOPhbAAAAWwAAAA8AAAAAAAAAAAAAAIABAAAAAHhsL3dvcmtib29rLnhtbFBLAQIUAxQAAAAAAK4NSV3UxK1ZVwAAAFcAAAAaAAAAAAAAAAAAAACAAYgAAAB4bC9fcmVscy93b3JrYm9vay54bWwucmVsc1BLAQIUAxQAAAAAAK4NSV3Vl0oKbAAAAPD///8YAAAAAAAAAAAAAACAARcBAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWxQSwUGAAAAAAMAAwDLAAAAuQEAAAAA"
}

private func date(_ hour: Int, _ minute: Int, day: Int = 8) -> Date {
    Calendar.app.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func interval(_ h1: Int, _ m1: Int, to h2: Int, _ m2: Int, day: Int = 8) -> WorkInterval {
    WorkInterval(start: date(h1, m1, day: day), end: date(h2, m2, day: day))
}

/// Small workbook: sheet "Oktober" with a header (shared strings, one rich text), an Excel
/// date and time row, an empty row and a text row; plus a second sheet "Notizen".
private let xlsxFixture = """
    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
    AQAA8AYAAAAA
"""

/// Layout of a typical university timesheet: no heading above the date column (C), Excel
/// dates and times, a holiday row with only a note, and totals below the table.
private let universityTimesheetFixture = """
    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
"""
