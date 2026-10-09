import SwiftUI

/// The day condensed into one "from, to, break" line for the timesheet at work.
struct TimesheetPanel: View {
    let job: Job
    let report: DayReport
    let isLive: Bool

    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let entry = TimesheetEntry(report: report, roundingMinutes: job.roundingMinutes) {
            let pause = job.breakFormat.strings(for: entry.breakDuration)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    TimesheetField(title: String(localized: "Start time"), value: entry.start.clockTime)
                    FieldDivider()
                    TimesheetField(
                        title: String(localized: "End time"),
                        value: entry.end.clockTime,
                        caption: isLive ? "provisional, timer running" : nil
                    )
                    FieldDivider()
                    TimesheetField(title: String(localized: "Break"), value: pause.display, copyValue: pause.copy)
                    FieldDivider()
                    TimesheetField(
                        title: String(localized: "Working time"),
                        value: entry.workedDuration.paddedClock,
                        caption: "follows automatically"
                    )
                }
                .card(padding: 0)

                HStack(alignment: .top, spacing: 12) {
                    Callout(systemImage: "info.circle", text: "\(explanation(for: entry))")

                    Menu {
                        Button("Copy as Text") { Pasteboard.copy(plainText(entry, pause: pause.copy)) }
                        Button("Copy as Table Row (Tab-Separated)") { Pasteboard.copy(tabSeparated(entry, pause: pause.copy)) }
                    } label: {
                        Label("Copy All", systemImage: "square.on.square")
                    } primaryAction: {
                        Pasteboard.copy(plainText(entry, pause: pause.copy))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.secondary(height: 28))
                    .fixedSize()
                }

                if settings.showsComplianceHints {
                    ComplianceNotice(report: report)
                }
            }
        } else {
            EmptyState(
                systemImage: "list.clipboard",
                title: "Nothing for the timesheet yet",
                message: "As soon as working time is tracked, you see start, end and break here, ready to copy."
            )
            .card(padding: 0)
        }
    }

    private func explanation(for entry: TimesheetEntry) -> String {
        let blocks = report.workIntervals.count
        var text: String
        if blocks > 1 {
            text = String(localized: "\(blocks) work blocks combined: the start is your first start, the break contains all interruptions, and the end follows from start, working time and break.")
        } else {
            text = String(localized: "One continuous work block without interruption.")
        }
        if job.roundingMinutes > 1 {
            text += " " + String(localized: "Rounded to \(job.roundingMinutes) minutes (tracked: \(report.workedDuration.clock) h work, \(report.breakDuration.clock) h break).")
        }
        return text
    }

    private func plainText(_ entry: TimesheetEntry, pause: String) -> String {
        """
        \(String(localized: "Start time")): \(entry.start.clockTime)
        \(String(localized: "End time")): \(entry.end.clockTime)
        \(String(localized: "Break")): \(pause)
        \(String(localized: "Working time")): \(entry.workedDuration.paddedClock)
        """
    }

    private func tabSeparated(_ entry: TimesheetEntry, pause: String) -> String {
        [entry.start.clockTime, entry.end.clockTime, pause].joined(separator: "\t")
    }
}

private struct TimesheetField: View {
    let title: String
    let value: String
    var copyValue: String?
    var caption: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(value: copyValue ?? value, help: "Copy \(title)")
            }
            Text(value)
                .font(.system(size: 26, weight: .medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
            Group {
                if let caption { Text(caption) } else { Text(verbatim: " ") }
            }
                .font(AppFont.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FieldDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(width: 1)
            .padding(.vertical, 12)
    }
}

struct ComplianceNotice: View {
    let report: DayReport

    var body: some View {
        let issues = Compliance.issues(for: report)
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(issues, id: \.self) { issue in
                    Callout(systemImage: "exclamationmark.triangle", tint: .amber, text: "\(message(for: issue))")
                }
            }
        }
    }

    private func message(for issue: ComplianceIssue) -> String {
        switch issue {
        case .insufficientBreak(let worked, let required, let taken):
            let threshold = worked > 9 * 3600 ? 9 : 6
            return String(localized: "With more than \(threshold) hours of work, at least \(required.wholeMinutes) minutes of break are required (§ 4 ArbZG, only interruptions of 15 minutes or more count). Counted so far: \(taken.clock) h.")
        case .exceedsDailyMaximum:
            return String(localized: "The daily maximum of 10 working hours is exceeded (§ 3 ArbZG).")
        }
    }
}
