import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// CSV in the app's number format, so Excel and Numbers open it directly. Where the decimal
/// separator is a comma, fields are separated by semicolons, as Excel expects there.
enum CSVExporter {
    static var header: [String] {
        [
            String(localized: "Date"), String(localized: "Weekday"), String(localized: "Start time"), String(localized: "End time"),
            String(localized: "Break"), String(localized: "Working time"), String(localized: "Working time (decimal)"),
            String(localized: "Target"), String(localized: "Balance"), String(localized: "Work blocks"),
            String(localized: "Absence"),
        ]
    }

    static var delimiter: String {
        Locale.app.decimalSeparator == "," ? ";" : ","
    }

    static func makeCSV(days: [DayStats], roundingMinutes: Int, includeEmptyWorkdays: Bool) -> String {
        var lines = [row(header)]

        for day in days {
            if let entry = TimesheetEntry(report: day.report, roundingMinutes: roundingMinutes) {
                let blocks = day.report.workIntervals
                    .map { "\($0.start.clockTime)-\($0.end.clockTime)" }
                    .joined(separator: " / ")
                lines.append(row([
                    day.day.numericDate,
                    day.day.weekdayName,
                    entry.start.clockTime,
                    entry.end.clockTime,
                    entry.breakDuration.paddedClock,
                    entry.workedDuration.paddedClock,
                    entry.workedDuration.decimalHours,
                    day.target.paddedClock,
                    (entry.workedDuration - day.target).signedClock,
                    blocks,
                    day.absence?.title ?? day.holiday?.title ?? "",
                ]))
            } else if (includeEmptyWorkdays && day.isWorkday) || day.absence != nil {
                lines.append(row([
                    day.day.numericDate,
                    day.day.weekdayName,
                    "", "", "", "", "",
                    day.target.paddedClock,
                    (-day.target).signedClock,
                    "",
                    day.absence?.title ?? day.holiday?.title ?? "",
                ]))
            }
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func row(_ fields: [String]) -> String {
        fields.map { escape($0) }.joined(separator: delimiter)
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { String($0) == delimiter || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

nonisolated struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // The byte order mark makes Excel recognize UTF-8 (umlauts in weekday names).
        FileWrapper(regularFileWithContents: Data(("\u{FEFF}" + text).utf8))
    }
}
