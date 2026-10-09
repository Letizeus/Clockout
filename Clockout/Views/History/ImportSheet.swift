import SwiftData
import SwiftUI

struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TimeTracker.self) private var tracker
    @Environment(JobStore.self) private var jobs
    @Query(sort: \WorkSession.start) private var allSessions: [WorkSession]

    @State private var source: ImportSource?
    @State private var sheetIndex = 0
    @State private var mapping = ImportMapping()
    @State private var strategy: ImportConflictStrategy = .skipExistingDays
    @State private var showsFileImporter = false
    @State private var isDropTargeted = false
    @State private var errorMessage: String?
    @State private var result: ImportResult?

    var body: some View {
        Group {
            if let source {
                ImportConfiguration(
                    source: source,
                    job: jobs.currentJob,
                    sheetIndex: $sheetIndex,
                    mapping: $mapping,
                    strategy: $strategy,
                    existingDays: Set(allSessions.filter { $0.jobID == jobs.currentJob.uuid }.map { Calendar.app.startOfDay(for: $0.start) }),
                    onChooseFile: { showsFileImporter = true },
                    onCancel: { dismiss() },
                    onImport: { rows in result = tracker.importRows(rows, into: jobs.currentJob, strategy: strategy) }
                )
            } else {
                filePicker
            }
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: ImportSource.contentTypes) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .onChange(of: sheetIndex) {
            if let source { mapping = TimesheetImporter.detectMapping(rows: source.sheets[sheetIndex].rows) }
        }
        .alert(
            "Import Finished",
            isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }),
            presenting: result
        ) { _ in
            Button("OK") { dismiss() }
        } message: { result in
            Text(result.summary)
        }
    }

    private var filePicker: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: "tablecells")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Import hours from CSV or Excel")
                    .font(.system(size: 15, weight: .semibold))
                Text("Drop a .csv or .xlsx file here, such as your timesheet or an export from this app.")
                    .font(AppFont.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
                Button("Choose File…") {
                    showsFileImporter = true
                }
                .buttonStyle(.primary(tint: .brand, height: 32))
                .padding(.top, 4)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(AppFont.body)
                        .foregroundStyle(.negative)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, minHeight: 300)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDropTargeted ? Color.brand.opacity(0.08) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isDropTargeted ? Color.brand : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            }
            .padding(20)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                load(url)
                return true
            } isTargeted: {
                isDropTargeted = $0
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 560)
    }

    private func load(_ url: URL) {
        do {
            let loaded = try ImportSource.load(from: url)
            errorMessage = nil
            sheetIndex = 0
            mapping = TimesheetImporter.detectMapping(rows: loaded.sheets[0].rows)
            source = loaded
        } catch {
            source = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct ImportConfiguration: View {
    let source: ImportSource
    let job: Job
    @Binding var sheetIndex: Int
    @Binding var mapping: ImportMapping
    @Binding var strategy: ImportConflictStrategy
    let existingDays: Set<Date>
    let onChooseFile: () -> Void
    let onCancel: () -> Void
    let onImport: ([ImportedRow]) -> Void

    private var sheet: ImportSheetData { source.sheets[min(sheetIndex, source.sheets.count - 1)] }

    var body: some View {
        let rows = TimesheetImporter.parse(rows: sheet.rows, mapping: mapping)
        let valid = rows.filter(\.isValid)
        let days = Set(valid.compactMap(\.day))
        let newDays = strategy == .skipExistingDays ? days.subtracting(existingDays) : days
        let importedRows = valid.filter { newDays.contains($0.day!) }

        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                mappingForm
                    .frame(width: 340)
                Divider()
                preview(rows: rows)
            }

            Divider()

            HStack(spacing: 12) {
                summary(rows: rows, importedRows: importedRows, days: newDays, skippedDays: days.count - newDays.count)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(newDays.isEmpty ? String(localized: "Import") : String(localized: "Import \(newDays.count) days")) {
                    onImport(rows)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newDays.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 980, height: 720)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: source.isExcel ? "tablecells" : "doc.text")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(sheet.rows.count) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("Import into")
                    .foregroundStyle(.secondary)
                JobBadge(job: job, font: .body.weight(.medium))
            }
            .padding(.trailing, 8)
            if source.sheets.count > 1 {
                Picker("Sheet", selection: $sheetIndex) {
                    ForEach(source.sheets.indices, id: \.self) { index in
                        Text(source.sheets[index].name).tag(index)
                    }
                }
                .fixedSize()
            }
            Button("Other File…", action: onChooseFile)
        }
        .padding(16)
    }

    private var mappingForm: some View {
        Form {
            Section {
                Picker("Headers in", selection: headerRowBinding) {
                    Text("No header row").tag(-1)
                    ForEach(0..<min(10, sheet.rows.count), id: \.self) { index in
                        Text("Row \(index + 1)").tag(index)
                    }
                }
                ForEach(ImportColumnRole.allCases) { role in
                    Picker(role.title, selection: columnBinding(role)) {
                        Text("Not present").tag(-1)
                        ForEach(0..<min(sheet.columnCount, 60), id: \.self) { column in
                            Text(columnLabel(column)).tag(column)
                        }
                    }
                }
            } header: {
                Text("Map Columns")
            } footer: {
                Text("Needs date, start and end, or the work blocks column of an export.")
                    .foregroundStyle(.secondary)
            }

            if mapping.columns[.pause] != nil {
                Section {
                    Picker("Break given in", selection: $mapping.pauseUnit) {
                        ForEach(PauseUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                } footer: {
                    Text("Places the break mid-day; start, end and working time stay exact.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Days already tracked") {
                Picker("Approach", selection: $strategy) {
                    ForEach(ImportConflictStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .overlayScrollers()
        .scrollBounceBehavior(.basedOnSize)
    }

    private func preview(rows: [ImportedRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Preview")
            if !mapping.canImport {
                EmptyState(
                    systemImage: "arrow.left.and.right",
                    title: "Map Columns",
                    message: "Choose the columns for date, start and end on the left."
                )
            } else if rows.isEmpty {
                EmptyState(systemImage: "tablecells", title: "No rows found", message: "This sheet contains no times.")
            } else {
                Table(rows) {
                    TableColumn("Row") { row in
                        Text("\(row.id)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(40)
                    TableColumn("Date") { row in
                        Text(row.day.map { "\($0.formatted(.dateTime.weekday(.abbreviated).locale(.app))) \($0.numericDate)" } ?? "-")
                            .monospacedDigit()
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn("Work blocks") { row in
                        Text(row.blocks.map { "\($0.start.clockTime)-\($0.end.clockTime)" }.joined(separator: ", "))
                            .monospacedDigit()
                            .help(row.note)
                    }
                    .width(min: 150, ideal: 200)
                    TableColumn("Work") { row in
                        Text(row.isValid ? "\(row.worked.clock) h" : "-")
                            .monospacedDigit()
                    }
                    .width(55)
                    TableColumn("Status") { row in
                        status(for: row)
                    }
                    .width(min: 140, ideal: 200)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func status(for row: ImportedRow) -> some View {
        let (text, symbol, color): (String, String, Color) = {
            if let error = row.error { return (error, "xmark.circle", .negative) }
            guard let day = row.day, existingDays.contains(day) else { return (String(localized: "New"), "checkmark.circle", .brand) }
            switch strategy {
            case .skipExistingDays: return (String(localized: "Already tracked"), "arrow.uturn.right.circle", .amber)
            case .replaceExistingDays: return (String(localized: "Replaces work blocks"), "arrow.triangle.2.circlepath", .amber)
            case .add: return (String(localized: "Will be added"), "plus.circle", .secondary)
            }
        }()
        return Label {
            Text(text).lineLimit(1)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .help(text)
    }

    private func summary(rows: [ImportedRow], importedRows: [ImportedRow], days: Set<Date>, skippedDays: Int) -> some View {
        let errors = rows.filter { $0.error != nil }.count
        let worked = importedRows.reduce(0) { $0 + $1.worked }
        let dayCount = String(localized: "\(days.count) days")
        var text = days.isEmpty
            ? String(localized: "Nothing to import.")
            : String(localized: "\(dayCount) with \(worked.clock) h will be imported.")
        if skippedDays > 0 {
            text += " " + String(localized: "\(skippedDays) days are already tracked and will be skipped.")
        }
        if errors > 0 {
            text += " " + String(localized: "\(errors) rows cannot be read and will be ignored.")
        }
        return Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: Bindings

    private var headerRowBinding: Binding<Int> {
        Binding(
            get: { mapping.headerRow ?? -1 },
            set: { mapping.headerRow = $0 < 0 ? nil : $0 }
        )
    }

    private func columnBinding(_ role: ImportColumnRole) -> Binding<Int> {
        Binding(
            get: { mapping.columns[role] ?? -1 },
            set: { column in
                if column >= 0 {
                    // A column can only have one meaning.
                    for (other, assigned) in mapping.columns where assigned == column && other != role {
                        mapping.columns[other] = nil
                    }
                    mapping.columns[role] = column
                } else {
                    mapping.columns[role] = nil
                }
            }
        )
    }

    private func columnLabel(_ column: Int) -> String {
        let letter = Self.columnLetter(column)
        let header = mapping.headerRow.flatMap { row in
            sheet.rows.indices.contains(row) && column < sheet.rows[row].count ? sheet.rows[row][column].text : nil
        }
        if let header, !header.isEmpty { return "\(letter): \(header)" }

        let firstData = (mapping.headerRow ?? -1) + 1
        let sample = sheet.rows.dropFirst(firstData).first { column < $0.count && !$0[column].isEmpty }?[column].text
        return sample.map { String(localized: "\(letter): e.g. \(String($0.prefix(20)))") } ?? String(localized: "Column \(letter)")
    }

    private static func columnLetter(_ index: Int) -> String {
        var index = index
        var letters = ""
        repeat {
            letters = String(UnicodeScalar(UInt8(65 + index % 26))) + letters
            index = index / 26 - 1
        } while index >= 0
        return letters
    }
}
