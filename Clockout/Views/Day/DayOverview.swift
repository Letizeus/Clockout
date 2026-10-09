import SwiftUI

enum DayDetailMode: String, CaseIterable, Identifiable {
    case actual
    case timesheet

    var id: Self { self }

    var title: String {
        switch self {
        case .actual: String(localized: "Actual times")
        case .timesheet: String(localized: "For the timesheet")
        }
    }
}

/// Summary, timeline and the two views on a day: the real blocks and the condensed timesheet entry.
struct DayOverview: View {
    let day: Date
    let job: Job
    let sessions: [WorkSession]
    let report: DayReport
    let now: Date

    @AppStorage("dayDetailMode") private var mode: DayDetailMode = .actual
    @State private var editorTarget: SessionEditorTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            summaryTiles

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Timeline")
                DayTimelineView(day: day, report: report, now: now)
                    .card(padding: 14)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    PillTabs(
                        options: DayDetailMode.allCases.map { ($0, $0.title) },
                        selection: $mode
                    )
                    Spacer()
                    Button {
                        editorTarget = .create(day: day, job: job)
                    } label: {
                        Label("Add Work Block", systemImage: "plus")
                    }
                    .buttonStyle(.secondary(height: 28))
                }

                switch mode {
                case .actual:
                    ActualTimesList(sessions: sessions, now: now) { editorTarget = .edit($0) }
                case .timesheet:
                    TimesheetPanel(job: job, report: report, isLive: sessions.contains(where: \.isRunning))
                }
            }
        }
        .sheet(item: $editorTarget) { SessionEditorView(target: $0) }
    }

    private var summaryTiles: some View {
        let target = job.rules.target(for: day, worked: report.workedDuration, now: now)
        let balance = report.workedDuration - target

        return HStack(spacing: 12) {
            StatTile(
                title: "Working time",
                value: "\(report.workedDuration.clock) h",
                caption: "\(report.workIntervals.count) work blocks"
            )
            StatTile(
                title: "Breaks",
                value: "\(report.breakDuration.clock) h",
                caption: report.breakIntervals.isEmpty ? "none" : "\(report.breakIntervals.count) breaks"
            )
            StatTile(
                title: "Presence",
                value: report.isEmpty ? "-" : "\(report.presenceDuration.clock) h",
                caption: presenceText.map { LocalizedStringResource("\($0)") }
            )
            // Work on a day without target still counts, like a holiday shift.
            let counts = target > 0 || report.workedDuration > 0
            StatTile(
                title: "Balance",
                value: counts ? "\(balance.signedClock) h" : "-",
                caption: target > 0 ? "Target \(target.clock) h" : "\(noTargetCaption)",
                valueColor: counts ? (balance >= 0 ? .positive : .negative) : .primary
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var noTargetCaption: String {
        if let dayOff = job.dayOff(on: day) { return String(localized: "\(dayOff), no target") }
        return String(localized: "No target for this day")
    }

    private var presenceText: String? {
        guard let first = report.firstStart, let last = report.lastEnd else { return nil }
        return String(localized: "\(first.clockTime) to \(last.clockTime)")
    }
}
