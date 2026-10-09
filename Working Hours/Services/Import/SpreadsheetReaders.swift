import Foundation
import UniformTypeIdentifiers

nonisolated enum ImportCell: Hashable {
    case empty
    case text(String)
    case number(Double)

    var isEmpty: Bool {
        switch self {
        case .empty: true
        case .text(let text): text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number: false
        }
    }

    var text: String {
        switch self {
        case .empty:
            return ""
        case .text(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .number(let value):
            if value == value.rounded() && abs(value) < 1e15 { return String(Int(value)) }
            return String(format: "%.4f", value)
        }
    }
}

nonisolated enum ImportError: LocalizedError {
    case unreadable
    case notExcel
    case legacyExcel
    case empty
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "The file could not be read.")
        case .notExcel: String(localized: "The file is not a valid Excel file (.xlsx).")
        case .legacyExcel: String(localized: "The old Excel format (.xls) is not supported. Please save the file in Excel as .xlsx or .csv.")
        case .empty: String(localized: "No data was found in the file.")
        case .tooLarge: String(localized: "The file is too large for a timesheet.")
        }
    }
}

nonisolated struct ImportSheetData: Hashable {
    let name: String
    let rows: [[ImportCell]]

    var columnCount: Int { rows.map(\.count).max() ?? 0 }
}

/// A loaded CSV or Excel file.
nonisolated struct ImportSource {
    let fileName: String
    let isExcel: Bool
    let sheets: [ImportSheetData]

    static var contentTypes: [UTType] {
        [
            .commaSeparatedText,
            .tabSeparatedText,
            .plainText,
            UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
            UTType(filenameExtension: "xls") ?? .data,
        ]
    }

    /// Timesheets are a few hundred KB; this keeps a wrong or hostile file from filling the memory.
    static let maximumFileSize = 20 * 1024 * 1024

    static func load(from url: URL) throws -> ImportSource {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumFileSize {
            throw ImportError.tooLarge
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadable
        }
        guard data.count <= maximumFileSize else { throw ImportError.tooLarge }
        return try load(data: data, fileName: url.lastPathComponent)
    }

    static func load(data: Data, fileName: String) throws -> ImportSource {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        let isZip = data.starts(with: [0x50, 0x4B, 0x03, 0x04])

        let sheets: [ImportSheetData]
        if fileExtension == "xls" && !isZip {
            throw ImportError.legacyExcel
        } else if isZip || fileExtension == "xlsx" || fileExtension == "xlsm" {
            sheets = try XLSXReader.read(data: data)
        } else {
            sheets = [ImportSheetData(name: "CSV", rows: CSVReader.read(data: data))]
        }

        let nonEmpty = sheets.filter { sheet in sheet.rows.contains { row in row.contains { !$0.isEmpty } } }
        guard !nonEmpty.isEmpty else { throw ImportError.empty }
        return ImportSource(fileName: fileName, isExcel: isZip, sheets: nonEmpty)
    }
}

// MARK: CSV

nonisolated enum CSVReader {
    static func read(data: Data) -> [[ImportCell]] {
        let text = decode(data)
        return parse(text, delimiter: detectDelimiter(text)).map { row in
            row.map { $0.isEmpty ? ImportCell.empty : ImportCell.text($0) }
        }
    }

    static func decode(_ data: Data) -> String {
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        if let text = String(data: data, encoding: .utf8) { return text }
        // Excel on Windows often saves CSV as Windows-1252.
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    static func detectDelimiter(_ text: String) -> Character {
        let lines = text.split(whereSeparator: \.isNewline).prefix(10)
        let candidates: [Character] = [";", "\t", ","]
        var best: (delimiter: Character, score: Int) = (";", 0)
        for candidate in candidates {
            let counts = lines.map { line in line.filter { $0 == candidate }.count }
            guard let first = counts.first, first > 0 else { continue }
            // Prefer delimiters that appear equally often on every line.
            let consistent = counts.filter { $0 == first }.count
            let score = consistent * 100 + first
            if score > best.score { best = (candidate, score) }
        }
        return best.delimiter
    }

    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var fieldWasQuoted = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil

        func finishField() {
            row.append(fieldWasQuoted ? field : field.trimmingCharacters(in: .whitespaces))
            field = ""
            fieldWasQuoted = false
        }

        func finishRow() {
            finishField()
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    let next = iterator.next()
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        pending = next
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" && field.trimmingCharacters(in: .whitespaces).isEmpty {
                inQuotes = true
                fieldWasQuoted = true
                field = ""
            } else if character == delimiter {
                finishField()
            } else if character.isNewline {
                finishRow()
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return rows
    }
}

// MARK: Excel

nonisolated enum XLSXReader {
    static func read(data: Data) throws -> [ImportSheetData] {
        let archive = try ZipArchive(data: data)
        guard let workbook = try archive.contents(of: "xl/workbook.xml") else { throw ImportError.notExcel }

        let relationships = try archive.contents(of: "xl/_rels/workbook.xml.rels").map(RelationshipsParser.parse) ?? [:]
        let sharedStrings = try archive.contents(of: "xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []

        return try WorkbookParser.parse(workbook).compactMap { sheet in
            guard let target = relationships[sheet.relationshipID] else { return nil }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard let xml = try archive.contents(of: path) else { return nil }
            return ImportSheetData(name: sheet.name, rows: WorksheetParser.parse(xml, sharedStrings: sharedStrings))
        }
    }
}

private nonisolated func localName(_ name: String) -> Substring {
    name.split(separator: ":").last ?? Substring(name)
}

private nonisolated final class WorkbookParser: NSObject, XMLParserDelegate {
    private var sheets: [(name: String, relationshipID: String)] = []

    static func parse(_ data: Data) -> [(name: String, relationshipID: String)] {
        let delegate = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.sheets
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard localName(elementName) == "sheet",
              let name = attributeDict["name"],
              let id = attributeDict.first(where: { $0.key == "r:id" || $0.key.hasSuffix(":id") })?.value
        else { return }
        sheets.append((name, id))
    }
}

private nonisolated final class RelationshipsParser: NSObject, XMLParserDelegate {
    private var targets: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let delegate = RelationshipsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.targets
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard localName(elementName) == "Relationship", let id = attributeDict["Id"], let target = attributeDict["Target"] else { return }
        targets[id] = target
    }
}

private nonisolated final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inText = false
    private var inPhonetic = false

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(elementName) {
        case "si": current = ""
        case "t": inText = !inPhonetic
        case "rPh": inPhonetic = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(elementName) {
        case "si": strings.append(current)
        case "t": inText = false
        case "rPh": inPhonetic = false
        default: break
        }
    }
}

private nonisolated final class WorksheetParser: NSObject, XMLParserDelegate {
    private static let maxRows = 20_000
    private static let maxColumns = 200

    private let sharedStrings: [String]
    private var cells: [Int: [Int: ImportCell]] = [:]
    private var rowIndex = 0
    private var nextRowIndex = 0
    private var columnIndex = 0
    private var nextColumnIndex = 0
    private var cellType: String?
    private var buffer = ""
    private var collecting = false

    private init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(_ data: Data, sharedStrings: [String]) -> [[ImportCell]] {
        let delegate = WorksheetParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.denseRows()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(elementName) {
        case "row":
            // Row numbers outside 1...maxRows are ignored. Clamping also keeps `rowIndex + 1` from overflowing.
            let number = attributeDict["r"].flatMap(Int.init) ?? nextRowIndex + 1
            rowIndex = (1...Self.maxRows).contains(number) ? number - 1 : Self.maxRows
            nextColumnIndex = 0
        case "c":
            columnIndex = min(attributeDict["r"].flatMap(Self.columnIndex(fromReference:)) ?? nextColumnIndex, Self.maxColumns)
            cellType = attributeDict["t"]
            buffer = ""
        case "v", "t":
            collecting = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch localName(elementName) {
        case "v", "t":
            collecting = false
        case "c":
            let cell = makeCell()
            if !cell.isEmpty && rowIndex < Self.maxRows && columnIndex < Self.maxColumns {
                cells[rowIndex, default: [:]][columnIndex] = cell
            }
            nextColumnIndex = columnIndex + 1
        case "row":
            nextRowIndex = min(rowIndex + 1, Self.maxRows)
        default:
            break
        }
    }

    private func makeCell() -> ImportCell {
        switch cellType {
        case "s":
            guard let index = Int(buffer), sharedStrings.indices.contains(index) else { return .empty }
            return .text(sharedStrings[index])
        case "inlineStr", "str", "d":
            return .text(buffer)
        case "b":
            return .text(buffer == "1" ? "TRUE" : "FALSE")
        case "e":
            return .empty
        default:
            guard !buffer.isEmpty else { return .empty }
            return Double(buffer).map(ImportCell.number) ?? .text(buffer)
        }
    }

    private func denseRows() -> [[ImportCell]] {
        guard let lastRow = cells.keys.max() else { return [] }
        return (0...lastRow).map { index in
            guard let row = cells[index], let lastColumn = row.keys.max() else { return [] }
            return (0...lastColumn).map { row[$0] ?? .empty }
        }
    }

    /// "B12" -> 1. `nil` without letters or with more than three (Excel ends at XFD), which would overflow.
    static func columnIndex(fromReference reference: String) -> Int? {
        var index = 0
        var letters = 0
        for scalar in reference.unicodeScalars {
            guard (65...90).contains(scalar.value) || (97...122).contains(scalar.value) else { break }
            letters += 1
            guard letters <= 3 else { return nil }
            index = index * 26 + Int((scalar.value & 0xDF) - 64)
        }
        return letters > 0 ? index - 1 : nil
    }
}
