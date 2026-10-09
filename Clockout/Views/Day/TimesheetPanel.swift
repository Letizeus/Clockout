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
                    if let explanation = explanation(for: entry) {
                        Callout(systemImage: "info.circle", text: "\(explanation)")
                    } else {
                        Spacer()
                    }

                    Menu {
                        Button("Copy as Text") { Pasteboard.copy(plainText(entry, pause: pause.copy)) }
                        Button("Copy as Table Row") { Pasteboard.copy(tabSeparated(entry, pause: pause.copy)) }
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
                title: "Nothing to copy yet",
                message: "Start, end and break appear here once you track time."
            )
            .card(padding: 0)
        }
    }

    /// How the line was made, when it differs from what was tracked. `nil` for one block without rounding.
    private func explanation(for entry: TimesheetEntry) -> String? {
        var parts: [String] = []
        let blocks = report.workIntervals.count
        if blocks > 1 {
            parts.append(String(localized: "Combines \(blocks) work blocks: first start, gaps as break."))
        }
        if job.roundingMinutes > 1 {
            parts.append(String(localized: "Rounded to \(job.roundingMinutes) min (tracked: \(report.workedDuration.clock) h work, \(report.breakDuration.clock) h break)."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
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
            return String(localized: "More than \(threshold) h of work needs \(required.wholeMinutes) min of break in parts of at least 15 min (§ 4 ArbZG). Counted: \(taken.clock) h.")
        case .exceedsDailyMaximum:
            return String(localized: "Over the 10-hour daily maximum (§ 3 ArbZG)")
        }
    }
}
