import Foundation

enum ImportColumnRole: String, CaseIterable, Identifiable {
    case date
    case start
    case end
    case pause
    case note
    case blocks

    var id: Self { self }

    var title: String {
        switch self {
        case .date: String(localized: "Date")
        case .start: String(localized: "Start time")
        case .end: String(localized: "End time")
        case .pause: String(localized: "Break")
        case .note: String(localized: "Note")
        case .blocks: String(localized: "Work blocks")
        }
    }

    /// Header names compared after lowercasing and removing accents.
    fileprivate var exactNames: Set<String> {
        switch self {
        case .date: ["datum", "date", "tag", "day", "arbeitstag"]
        case .start: ["beginn", "start", "von", "kommen", "kommt", "anfang", "arbeitsbeginn", "startzeit", "begin", "from", "start time", "check in"]
        case .end: ["ende", "end", "bis", "gehen", "geht", "feierabend", "endzeit", "arbeitsende", "to", "end time", "check out"]
        case .pause: ["pause", "pausen", "pausenzeit", "break", "breaks", "unterbrechung"]
        case .note: ["notiz", "notizen", "bemerkung", "bemerkungen", "anmerkung", "anmerkungen", "kommentar", "beschreibung", "tatigkeit", "projekt", "aufgabe", "note", "notes", "comment", "description"]
        case .blocks: ["arbeitsblocke", "blocke", "zeitblocke", "work blocks", "blocks"]
        }
    }

    fileprivate var partialNames: [String] {
        switch self {
        case .date: ["datum", "date"]
        case .start: ["beginn", "start", "kommen", "anfang"]
        case .end: ["ende", "gehen", "endzeit"]
        case .pause: ["pause", "break"]
        case .note: ["notiz", "bemerk", "anmerk", "beschreib", "tatigkeit", "kommentar", "comment", "projekt"]
        case .blocks: ["arbeitsblock", "blocke", "block"]
        }
    }

    /// Specific roles first, so e.g. "Arbeitsblöcke" is not taken for something else.
    fileprivate static let detectionOrder: [ImportColumnRole] = [.blocks, .date, .start, .end, .pause, .note]
}

enum PauseUnit: String, CaseIterable, Identifiable {
    case automatic
    case clock
    case minutes
    case decimalHours

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .clock: String(localized: "Hours:minutes (0:30)")
        case .minutes: String(localized: "Minutes (30)")
        case .decimalHours: String(localized: "Decimal hours (0.5)")
        }
    }
}

enum ImportConflictStrategy: String, CaseIterable, Identifiable {
    case skipExistingDays
    case replaceExistingDays
    case add

    var id: Self { self }

    var title: String {
        switch self {
        case .skipExistingDays: String(localized: "Skip")
        case .replaceExistingDays: String(localized: "Replace existing entries")
        case .add: String(localized: "Add as well")
        }
    }
}

struct ImportMapping: Equatable {
    /// Index of the header row. Data starts on the row after it.
    var headerRow: Int?
    var columns: [ImportColumnRole: Int] = [:]
    var pauseUnit: PauseUnit = .automatic

    var canImport: Bool {
        guard columns[.date] != nil || columns[.start] != nil else { return false }
        return columns[.blocks] != nil || (columns[.start] != nil && columns[.end] != nil)
    }
}

struct ImportedRow: Identifiable, Equatable {
    /// 1-based row number in the file.
    let id: Int
    let day: Date?
    let blocks: [WorkInterval]
    let note: String
    let error: String?

    var worked: TimeInterval { blocks.reduce(0) { $0 + $1.duration } }
    var isValid: Bool { error == nil && day != nil && !blocks.isEmpty }
}

struct ImportResult: Equatable {
    var importedDays = 0
    var createdBlocks = 0
    var replacedDays = 0
    var skippedDays = 0

    var summary: String {
        let days = String(localized: "\(importedDays) days")
        let blocks = String(localized: "with \(createdBlocks) work blocks")
        var text = String(localized: "Imported \(days) \(blocks).")
        if replacedDays > 0 {
            text += " " + String(localized: "Existing entries were replaced on \(replacedDays) days.")
        }
        if skippedDays > 0 {
            text += " " + String(localized: "\(skippedDays) days were skipped because they already had entries.")
        }
        return text
    }
}

/// Turns spreadsheet rows into work blocks.
///
/// Rows with only "from, to, break" do not say when the break was taken; it is placed
/// in the middle of the working time, which keeps start, end and worked time exact.
enum TimesheetImporter {
    // MARK: Mapping

    static func detectMapping(rows: [[ImportCell]]) -> ImportMapping {
        var best: (row: Int, columns: [ImportColumnRole: Int])?
        for index in rows.indices.prefix(10) {
            let columns = matchHeader(rows[index])
            if columns.count >= 2 && columns.count > (best?.columns.count ?? 0) {
                best = (index, columns)
            }
        }
        if var best {
            // Timesheets often leave the date column without a heading.
            if best.columns[.date] == nil,
               let column = dateColumn(in: Array(rows.dropFirst(best.row + 1)), excluding: Set(best.columns.values)) {
                best.columns[.date] = column
            }
            return ImportMapping(headerRow: best.row, columns: best.columns)
        }
        return ImportMapping(headerRow: nil, columns: guessColumnsByContent(rows))
    }

    /// The first column whose cells are mostly dates.
    private static func dateColumn(in rows: [[ImportCell]], excluding excluded: Set<Int> = []) -> Int? {
        let sample = rows.filter { $0.contains { !$0.isEmpty } }.prefix(60)
        guard !sample.isEmpty else { return nil }
        let columnCount = sample.map(\.count).max() ?? 0
        return (0..<columnCount).first { column in
            guard !excluded.contains(column) else { return false }
            let hits = sample.filter { column < $0.count && parseDate($0[column]) != nil }.count
            return Double(hits) / Double(sample.count) >= 0.6
        }
    }

    private static func matchHeader(_ row: [ImportCell]) -> [ImportColumnRole: Int] {
        let names = row.map { normalize($0.text) }
        var result: [ImportColumnRole: Int] = [:]
        var used = Set<Int>()

        for role in ImportColumnRole.detectionOrder {
            let free = names.indices.filter { !used.contains($0) && !names[$0].isEmpty }
            let exact = free.first { role.exactNames.contains(names[$0]) }
            let partial = free.first { index in role.partialNames.contains { names[index].contains($0) } }
            if let column = exact ?? partial {
                result[role] = column
                used.insert(column)
            }
        }
        return result
    }

    /// Without a header row: the first column full of dates is the date, then time columns in order.
    private static func guessColumnsByContent(_ rows: [[ImportCell]]) -> [ImportColumnRole: Int] {
        let sample = rows.filter { $0.contains { !$0.isEmpty } }.prefix(20)
        guard !sample.isEmpty else { return [:] }
        let columnCount = sample.map(\.count).max() ?? 0

        func ratio(_ column: Int, _ test: (ImportCell) -> Bool) -> Double {
            let hits = sample.filter { column < $0.count && test($0[column]) }.count
            return Double(hits) / Double(sample.count)
        }

        var result: [ImportColumnRole: Int] = [:]
        let date = dateColumn(in: Array(sample))
        result[.date] = date
        var timeColumns: [Int] = []
        for column in 0..<columnCount where column != date {
            if ratio(column, { looksLikeTime($0) }) >= 0.6 {
                timeColumns.append(column)
            }
        }
        for (role, column) in zip([ImportColumnRole.start, .end, .pause], timeColumns) {
            result[role] = column
        }
        return result
    }

    private static func looksLikeTime(_ cell: ImportCell) -> Bool {
        switch cell {
        case .number(let value): value >= 0 && value < 1
        case .text(let text): text.contains(":") && parseTime(cell) != nil
        case .empty: false
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .app)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
    }

    // MARK: Rows

    static func parse(rows: [[ImportCell]], mapping: ImportMapping, calendar: Calendar = .app) -> [ImportedRow] {
        let firstDataRow = (mapping.headerRow ?? -1) + 1
        guard firstDataRow < rows.count else { return [] }

        var result: [ImportedRow] = []
        for index in firstDataRow..<rows.count {
            let row = rows[index]
            func cell(_ role: ImportColumnRole) -> ImportCell {
                guard let column = mapping.columns[role], column < row.count else { return .empty }
                return row[column]
            }

            let start = cell(.start), end = cell(.end), blocks = cell(.blocks)
            // Weekends or empty template lines.
            if start.isEmpty && end.isEmpty && blocks.isEmpty { continue }

            result.append(parseRow(
                number: index + 1,
                date: cell(.date),
                start: start,
                end: end,
                pause: cell(.pause),
                note: cell(.note).text,
                blocks: blocks,
                pauseUnit: mapping.pauseUnit,
                calendar: calendar
            ))
        }
        return result
    }

    private static func parseRow(
        number: Int,
        date: ImportCell,
        start: ImportCell,
        end: ImportCell,
        pause: ImportCell,
        note: String,
        blocks: ImportCell,
        pauseUnit: PauseUnit,
        calendar: Calendar
    ) -> ImportedRow {
        func failure(_ day: Date?, _ message: String) -> ImportedRow {
            ImportedRow(id: number, day: day, blocks: [], note: note, error: message)
        }

        guard let day = parseDate(date, calendar: calendar) ?? parseDate(start, calendar: calendar) else {
            return failure(nil, date.isEmpty ? String(localized: "Date missing") : String(localized: "Date not readable: \(date.text)"))
        }

        if !blocks.isEmpty {
            let ranges = parseBlocks(blocks.text)
            guard !ranges.isEmpty else { return failure(day, String(localized: "Work blocks not readable")) }
            return ImportedRow(id: number, day: day, blocks: ranges.map { interval(day, $0.0, $0.1, calendar) }, note: note, error: nil)
        }

        guard let startMinutes = parseTime(start) else {
            return failure(day, start.isEmpty ? String(localized: "Start missing") : String(localized: "Start not readable: \(start.text)"))
        }
        guard var endMinutes = parseTime(end) else {
            return failure(day, end.isEmpty ? String(localized: "End missing") : String(localized: "End not readable: \(end.text)"))
        }
        if endMinutes == startMinutes { return failure(day, String(localized: "Start and end are the same")) }
        if endMinutes < startMinutes { endMinutes += 24 * 60 }

        let span = endMinutes - startMinutes
        // When start is an Excel time, a break below 1 is an Excel time too (0.1875 is 4:30).
        let startIsExcelTime: Bool
        if case .number = start { startIsExcelTime = true } else { startIsExcelTime = false }
        guard let pauseMinutes = parseDuration(pause, unit: pauseUnit, excelTimes: startIsExcelTime) else {
            return failure(day, String(localized: "Break not readable: \(pause.text)"))
        }
        guard pauseMinutes < span else { return failure(day, String(localized: "Break is longer than the time present")) }

        let ranges: [(Int, Int)]
        if pauseMinutes > 0 {
            let firstEnd = startMinutes + (span - pauseMinutes) / 2
            ranges = [(startMinutes, firstEnd), (firstEnd + pauseMinutes, endMinutes)]
        } else {
            ranges = [(startMinutes, endMinutes)]
        }
        return ImportedRow(id: number, day: day, blocks: ranges.map { interval(day, $0.0, $0.1, calendar) }, note: note, error: nil)
    }

    private static func interval(_ day: Date, _ start: Int, _ end: Int, _ calendar: Calendar) -> WorkInterval {
        WorkInterval(
            start: calendar.date(byAdding: .minute, value: start, to: day) ?? day,
            end: calendar.date(byAdding: .minute, value: end, to: day) ?? day
        )
    }

    // MARK: Values

    private static let isoDate = try! NSRegularExpression(pattern: #"(\d{4})-(\d{1,2})-(\d{1,2})"#)
    private static let germanDate = try! NSRegularExpression(pattern: #"(\d{1,2})\.(\d{1,2})\.(\d{2,4})"#)
    private static let slashDate = try! NSRegularExpression(pattern: #"(\d{1,2})/(\d{1,2})/(\d{2,4})"#)
    private static let clockTime = try! NSRegularExpression(pattern: #"(\d{1,2})\s*[:.h]\s*(\d{2})(?:[:.](\d{2}))?"#)
    private static let blockRange = try! NSRegularExpression(
        pattern: #"(\d{1,2}[:.]\d{2})\s*(?:-|\x{2013}|bis)\s*(\d{1,2}[:.]\d{2})"#,
        options: [.caseInsensitive]
    )

    /// Start of the day, from text like "08.10.2026", "2026-10-08", "Do., 08.10.26" or an Excel date number.
    static func parseDate(_ cell: ImportCell, calendar: Calendar = .app) -> Date? {
        switch cell {
        case .empty:
            return nil
        case .number(let value):
            // Excel stores dates as days since 30.12.1899; plausible range 1954 to 2119.
            guard value >= 20_000, value < 80_000,
                  let base = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))
            else { return nil }
            return calendar.date(byAdding: .day, value: Int(value.rounded(.down)), to: base)
        case .text(let text):
            return dateMatch(in: text, calendar: calendar)?.date
        }
    }

    private static func dateMatch(in text: String, calendar: Calendar) -> (date: Date, range: Range<String.Index>)? {
        let candidates: [(NSRegularExpression, (Int, Int, Int))] = [
            (isoDate, (3, 2, 1)),
            (germanDate, (1, 2, 3)),
            (slashDate, (1, 2, 3)),
        ]
        for (regex, order) in candidates {
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range, in: text)
            else { continue }
            func group(_ index: Int) -> Int? {
                Range(match.range(at: index), in: text).flatMap { Int(text[$0]) }
            }
            guard let day = group(order.0), let month = group(order.1), var year = group(order.2) else { continue }
            if year < 100 { year += 2000 }
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components),
                  calendar.component(.day, from: date) == day,
                  calendar.component(.month, from: date) == month
            else { continue }
            return (calendar.startOfDay(for: date), range)
        }
        return nil
    }

    /// Minutes since midnight, from "8:00", "08.30", "16:45:00", "4:30 PM", "1630" or an Excel time.
    static func parseTime(_ cell: ImportCell) -> Int? {
        switch cell {
        case .empty:
            return nil
        case .number(let value):
            guard value.isFinite, value >= 0 else { return nil }
            if value == value.rounded(), value <= 24 { return Int(value) * 60 }
            let fraction = value - value.rounded(.down)
            return Int((fraction * 24 * 60).rounded()) % (24 * 60)
        case .text(var text):
            text = text.lowercased()
            // "08.10.2026 08:00" must not read the date as a time.
            if let match = dateMatch(in: text, calendar: .app) {
                text.removeSubrange(match.range)
            }
            text = text.trimmingCharacters(in: .whitespaces)

            var hour: Int
            var minute = 0
            if let match = clockTime.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let hourRange = Range(match.range(at: 1), in: text),
               let minuteRange = Range(match.range(at: 2), in: text),
               let parsedHour = Int(text[hourRange]),
               let parsedMinute = Int(text[minuteRange]) {
                hour = parsedHour
                minute = parsedMinute
            } else {
                // "8", "8 Uhr", "1630"
                let digits = text.replacingOccurrences(of: "uhr", with: "").trimmingCharacters(in: .whitespaces)
                guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let number = Int(digits) else { return nil }
                switch digits.count {
                case 1, 2: hour = number
                case 3, 4: hour = number / 100; minute = number % 100
                default: return nil
                }
            }

            if text.contains("pm") && hour < 12 { hour += 12 }
            if text.contains("am") && hour == 12 { hour = 0 }
            guard (0...24).contains(hour), (0..<60).contains(minute), hour * 60 + minute <= 24 * 60 else { return nil }
            return hour * 60 + minute
        }
    }

    /// Break length in minutes. Empty means no break; `nil` means unreadable.
    static func parseDuration(_ cell: ImportCell, unit: PauseUnit, excelTimes: Bool = false) -> Int? {
        switch cell {
        case .empty:
            return 0
        case .number(let value):
            switch unit {
            case .clock: return breakMinutes(value * 24 * 60)
            case .minutes: return breakMinutes(value)
            case .decimalHours: return breakMinutes(value * 60)
            case .automatic:
                if value < 1 && excelTimes {
                    return breakMinutes(value * 24 * 60)
                }
                if value < 1 {
                    // Excel times are fractions of a day; 0.0208 is 0:30. Large fractions are decimal hours.
                    let asDayFraction = value * 24 * 60
                    return breakMinutes(asDayFraction <= 240 ? asDayFraction : value * 60)
                }
                return breakMinutes(value == value.rounded() ? value : value * 60)
            }
        case .text(let raw):
            let text = raw.lowercased().trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text == "-" { return 0 }

            if text.contains(":") {
                let parts = text.split(separator: ":").map { Int($0.filter(\.isNumber)) }
                guard parts.count >= 2, let hours = parts[0], let minutes = parts[1], hours <= 24, minutes <= 24 * 60 else { return nil }
                return breakMinutes(Double(hours * 60 + minutes))
            }

            let numeric = text.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
            guard let value = Double(numeric) else { return nil }
            if text.contains("min") { return breakMinutes(value) }
            if text.contains("h") || text.contains("std") { return breakMinutes(value * 60) }

            switch unit {
            case .minutes: return breakMinutes(value)
            case .decimalHours: return breakMinutes(value * 60)
            case .automatic, .clock: return breakMinutes(numeric.contains(".") ? value * 60 : value)
            }
        }
    }

    /// Whole minutes, or `nil` for values that cannot be a break: not finite, negative or longer than a day.
    /// Converting larger numbers to `Int` would crash on files with nonsense values.
    private static func breakMinutes(_ minutes: Double) -> Int? {
        guard minutes.isFinite, minutes >= 0, minutes <= 24 * 60 else { return nil }
        return Int(minutes.rounded())
    }

    /// "08:00-12:00 / 12:30-16:30" (the format of this app's CSV export).
    static func parseBlocks(_ text: String) -> [(Int, Int)] {
        blockRange.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let startRange = Range(match.range(at: 1), in: text),
                  let endRange = Range(match.range(at: 2), in: text),
                  let start = parseTime(.text(String(text[startRange]))),
                  var end = parseTime(.text(String(text[endRange])))
            else { return nil }
            if end <= start { end += 24 * 60 }
            return (start, end)
        }
    }
}
