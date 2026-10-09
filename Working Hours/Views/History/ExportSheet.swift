import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JobStore.self) private var jobs
    @Query(sort: \WorkSession.start) private var allSessions: [WorkSession]

    @State private var from: Date = Calendar.app.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var to: Date = .now
    @State private var includeEmptyWorkdays = false
    @State private var document: CSVDocument?
    @State private var errorMessage: String?

    private var interval: DateInterval {
        let calendar = Calendar.app
        let start = calendar.startOfDay(for: min(from, to))
        let lastDay = calendar.startOfDay(for: max(from, to))
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        return DateInterval(start: start, end: end)
    }

    var body: some View {
        let job = jobs.currentJob
        let sessions = allSessions.filter { $0.jobID == job.uuid }
        let days = WorkStatistics.days(in: interval, sessions: sessions, settings: job.rules, now: .now)
        let summary = PeriodSummary(days: days)

        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Job") {
                        JobBadge(job: job, font: .body)
                    }
                }
                Section("Range") {
                    LabeledContent("From") {
                        ThemedDateField(date: $from)
                    }
                    LabeledContent("To") {
                        ThemedDateField(date: $to)
                    }
                    HStack {
                        Spacer()
                        Button("This Week") { setRange(.weekOfYear, offset: 0) }
                        Button("This Month") { setRange(.month, offset: 0) }
                        Button("Last Month") { setRange(.month, offset: -1) }
                    }
                    .controlSize(.small)
                    Toggle("Include workdays without entries", isOn: $includeEmptyWorkdays)
                }

                Section {
                    LabeledContent("Tracked days", value: "\(summary.trackedDays)")
                    LabeledContent("Total working time", value: "\(summary.worked.clock) h")
                    LabeledContent("Balance", value: "\(summary.balance.signedClock) h")
                } header: {
                    Text("Preview")
                } footer: {
                    Text("One row per day with start, end and break for the timesheet, plus the individual work blocks. The file uses your number format and opens directly in Excel or Numbers.")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.negative)
                }
            }
            .formStyle(.grouped)
            .overlayScrollers()
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    document = CSVDocument(text: CSVExporter.makeCSV(
                        days: days,
                        roundingMinutes: job.roundingMinutes,
                        includeEmptyWorkdays: includeEmptyWorkdays
                    ))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(summary.trackedDays == 0 && !includeEmptyWorkdays)
            }
            .padding(16)
        }
        .frame(width: 480)
        .fileExporter(
            isPresented: Binding(get: { document != nil }, set: { if !$0 { document = nil } }),
            document: document,
            contentType: .commaSeparatedText,
            defaultFilename: String(localized: "Working hours \(jobs.currentJob.displayName) \(interval.start.formatted(.iso8601.year().month().day())) to \(interval.end.addingTimeInterval(-1).formatted(.iso8601.year().month().day()))")
        ) { result in
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setRange(_ component: Calendar.Component, offset: Int) {
        let calendar = Calendar.app
        guard
            let reference = calendar.date(byAdding: component, value: offset, to: .now),
            let range = calendar.dateInterval(of: component, for: reference)
        else { return }
        from = range.start
        to = min(range.end.addingTimeInterval(-1), .now)
    }
}
