import Charts
import SwiftData
import SwiftUI

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: Self { self }

    var title: String {
        switch self {
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        case .year: String(localized: "Year")
        }
    }

    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    func interval(containing date: Date, calendar: Calendar = .app) -> DateInterval {
        calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 86_400)
    }

    func title(for interval: DateInterval, calendar: Calendar = .app) -> String {
        let lastDay = interval.end.addingTimeInterval(-1)
        switch self {
        case .week:
            let week = calendar.component(.weekOfYear, from: interval.start)
            let first = interval.start.formatted(.dateTime.day().month(.abbreviated).locale(.app))
            let last = lastDay.formatted(.dateTime.day().month(.abbreviated).year().locale(.app))
            return String(localized: "Week \(week): \(first) to \(last)")
        case .month:
            return interval.start.monthTitle
        case .year:
            return interval.start.formatted(.dateTime.year().locale(.app))
        }
    }
}

struct StatisticsView: View {
    @Query(sort: \WorkSession.start) private var allSessions: [WorkSession]
    @Environment(JobStore.self) private var jobs
    @State private var period: StatsPeriod = .week
    @State private var editsCarryOver = false
    @State private var anchor: Date = .now

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .navigationTitle("Statistics")
        .navigationSubtitle(job.displayName)
    }

    private var job: Job { jobs.currentJob }

    private var sessions: [WorkSession] {
        let jobID = job.uuid
        return allSessions.filter { $0.jobID == jobID }
    }

    private struct ChartPoint: Identifiable {
        let date: Date
        let worked: TimeInterval
        let target: TimeInterval
        var id: Date { date }
        var metTarget: Bool { target > 0 && worked >= target }
    }

    private struct MonthRow {
        let month: Date
        let summary: PeriodSummary
    }

    private func content(now: Date) -> some View {
        let interval = period.interval(containing: anchor)
        let days = WorkStatistics.days(in: interval, sessions: sessions, settings: job.rules, now: now)
        let summary = PeriodSummary(days: days)
        let overall = overallSummary(now: now)

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(interval: interval, now: now)

                HStack(spacing: 12) {
                    StatTile(
                        title: "Working time",
                        value: "\(summary.worked.clock) h",
                        caption: "\(summary.trackedDays) days tracked"
                    )
                    StatTile(
                        title: "Target",
                        value: "\(summary.target.clock) h",
                        caption: "\(targetCaption(summary))"
                    )
                    StatTile(
                        title: "Balance",
                        value: "\(summary.balance.signedClock) h",
                        caption: "in this period",
                        valueColor: summary.balance >= 0 ? .positive : .negative
                    )
                    StatTile(
                        title: "Average",
                        value: "\(summary.averagePerTrackedDay.clock) h",
                        caption: "per tracked day"
                    )
                    StatTile(
                        title: "Total balance",
                        value: overall.map { "\($0.balance.signedClock) h" } ?? "-",
                        caption: overall.map { "\(overallCaption($0))" },
                        valueColor: overall == nil ? .primary : ((overall?.balance ?? 0) >= 0 ? .positive : .negative)
                    )
                    .overlay(alignment: .topTrailing) {
                        Button {
                            editsCarryOver = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.ghost)
                        .padding(6)
                        .help("Set carry-over")
                        .popover(isPresented: $editsCarryOver, arrowEdge: .bottom) {
                            CarryOverPopover(job: job)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("Hours Worked")
                    chart(points: chartPoints(days: days), interval: interval)
                        .card()
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(period == .year ? "Months" : "Days for the timesheet") {
                        if period != .year {
                            Button {
                                Pasteboard.copy(tabSeparated(days: days))
                            } label: {
                                Label("Copy Table", systemImage: "square.on.square")
                            }
                            .buttonStyle(.secondary(height: 26))
                        }
                    }
                    if period == .year {
                        monthTable(days: days)
                    } else {
                        dayTable(days: days)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
            .overlayScrollers()
        }
    }

    // MARK: Header

    private func header(interval: DateInterval, now: Date) -> some View {
        HStack(spacing: 6) {
            PillTabs(options: StatsPeriod.allCases.map { ($0, $0.title) }, selection: $period)

            Spacer()

            Text(period.title(for: interval))
                .font(AppFont.bodyMedium.monospacedDigit())
                .padding(.trailing, 6)

            Button {
                shift(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.ghost)
            .help("Previous period")

            Button {
                shift(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.ghost)
            .disabled(interval.end > now)
            .help("Next period")

            Button("Today") {
                anchor = .now
            }
            .buttonStyle(.secondary(height: 26))
            .disabled(interval.contains(now))
        }
    }

    private func shift(by value: Int) {
        anchor = Calendar.app.date(byAdding: period.component, value: value, to: anchor) ?? anchor
    }

    // MARK: Chart

    private func chartPoints(days: [DayStats]) -> [ChartPoint] {
        guard period == .year else {
            return days.map { ChartPoint(date: $0.day, worked: $0.worked, target: $0.target) }
        }
        let calendar = Calendar.app
        return Dictionary(grouping: days) { calendar.dateInterval(of: .month, for: $0.day)?.start ?? $0.day }
            .map { month, items in
                ChartPoint(
                    date: month,
                    worked: items.reduce(0) { $0 + $1.worked },
                    target: items.reduce(0) { $0 + $1.target }
                )
            }
            .sorted { $0.date < $1.date }
    }

    private func chart(points: [ChartPoint], interval: DateInterval) -> some View {
        let unit: Calendar.Component = period == .year ? .month : .day
        let dailyTargetHours = job.dailyTarget / 3600

        return Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: unit),
                    y: .value("Hours", point.worked / 3600)
                )
                .foregroundStyle(point.metTarget ? Color.brand : Color.brand.opacity(0.45))
                .cornerRadius(3)
            }
            if period != .year && dailyTargetHours > 0 {
                RuleMark(y: .value("Target", dailyTargetHours))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Target \(job.dailyTarget.clock) h")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartXAxis {
            switch period {
            case .week:
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                        .font(AppFont.caption)
                }
            case .month:
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                        .font(AppFont.caption)
                }
            case .year:
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .font(AppFont.caption)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.hairline)
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(Int(hours)) h")
                            .font(AppFont.caption)
                    }
                }
            }
        }
        .frame(height: 220)
    }

    // MARK: Tables

    private func visibleDays(_ days: [DayStats]) -> [DayStats] {
        days.filter { !$0.report.isEmpty || $0.target > 0 || (period == .week && $0.isWorkday) }
    }

    private func dayTable(days: [DayStats]) -> some View {
        let rows = visibleDays(days)

        return VStack(spacing: 0) {
            TableHeaderRow(columns: [String(localized: "Day"), String(localized: "Start time"), String(localized: "End time"), String(localized: "Break"), String(localized: "Working time"), String(localized: "Balance")])
            if rows.isEmpty {
                EmptyState(systemImage: "calendar", title: "Nothing tracked", message: "Tracked days appear here.")
            }
            ForEach(rows) { day in
                let entry = TimesheetEntry(report: day.report, roundingMinutes: job.roundingMinutes)
                TableDataRow(
                    cells: [
                        day.day.shortDayTitle,
                        entry?.start.clockTime ?? "-",
                        entry?.end.clockTime ?? "-",
                        entry.map { job.breakFormat.strings(for: $0.breakDuration).display } ?? "-",
                        entry.map { "\($0.workedDuration.clock) h" } ?? "-",
                        day.target > 0 || day.worked > 0 ? "\(day.balance.signedClock) h" : "-",
                    ],
                    lastColor: day.target == 0 && day.worked == 0 ? .secondary : (day.balance >= 0 ? .positive : .negative),
                    isMuted: day.report.isEmpty
                )
            }
        }
        .card(padding: 0)
    }

    private func monthTable(days: [DayStats]) -> some View {
        let calendar = Calendar.app
        let grouped: [Date: [DayStats]] = Dictionary(grouping: days) { (day: DayStats) -> Date in
            calendar.dateInterval(of: .month, for: day.day)?.start ?? day.day
        }
        let months: [MonthRow] = grouped
            .map { MonthRow(month: $0.key, summary: PeriodSummary(days: $0.value)) }
            .filter { $0.summary.trackedDays > 0 || $0.summary.target > 0 }
            .sorted { $0.month < $1.month }

        return VStack(spacing: 0) {
            TableHeaderRow(columns: [String(localized: "Month"), String(localized: "Days"), String(localized: "Working time"), String(localized: "Target"), String(localized: "Balance")])
            if months.isEmpty {
                EmptyState(systemImage: "calendar", title: "Nothing tracked", message: "Tracked months appear here.")
            }
            ForEach(months, id: \.month) { month in
                TableDataRow(
                    cells: [
                        month.month.formatted(.dateTime.month(.wide).locale(.app)),
                        "\(month.summary.trackedDays)",
                        "\(month.summary.worked.clock) h",
                        "\(month.summary.target.clock) h",
                        "\(month.summary.balance.signedClock) h",
                    ],
                    lastColor: month.summary.balance >= 0 ? .positive : .negative
                )
            }
        }
        .card(padding: 0)
    }

    private func tabSeparated(days: [DayStats]) -> String {
        visibleDays(days).map { day in
            guard let entry = TimesheetEntry(report: day.report, roundingMinutes: job.roundingMinutes) else {
                return [day.day.numericDate, "", "", ""].joined(separator: "\t")
            }
            return [
                day.day.numericDate,
                entry.start.clockTime,
                entry.end.clockTime,
                job.breakFormat.strings(for: entry.breakDuration).copy,
            ].joined(separator: "\t")
        }
        .joined(separator: "\n")
    }

    // MARK: Overall

    private func overallSummary(now: Date) -> OverallBalance? {
        WorkStatistics.overallBalance(
            intervals: sessions.map { $0.interval(now: now) },
            settings: job.rules,
            carryOver: job.carryOver,
            now: now
        )
    }

    private func targetCaption(_ summary: PeriodSummary) -> String {
        let holidays = String(localized: "\(summary.holidayDays) holidays")
        let absences = String(localized: "\(summary.absenceDays) absence days")
        switch (summary.holidayDays > 0, summary.absenceDays > 0) {
        case (true, true): return String(localized: "excluding \(holidays) and \(absences)")
        case (true, false): return String(localized: "excluding \(holidays)")
        case (false, true): return String(localized: "excluding \(absences)")
        case (false, false):
            return job.targetOnlyOnTrackedDays ? String(localized: "only tracked days") : String(localized: "all workdays")
        }
    }

    private func overallCaption(_ overall: OverallBalance) -> String {
        guard job.carryOver != nil else { return String(localized: "since \(overall.since.numericDate)") }
        return String(localized: "incl. carry-over \(overall.carryOver.signedClock) h")
    }
}

/// Column layout shared by the header and the rows: a fixed first column, then equal columns;
/// the last two (durations) are right-aligned.
private struct TableColumns {
    static let firstWidth: CGFloat = 140

    static func alignment(_ index: Int, count: Int) -> Alignment {
        index >= count - 2 ? .trailing : .leading
    }
}

private struct TableCell: ViewModifier {
    let index: Int
    let count: Int

    func body(content: Content) -> some View {
        if index == 0 {
            content.frame(width: TableColumns.firstWidth, alignment: .leading)
        } else {
            content.frame(maxWidth: .infinity, alignment: TableColumns.alignment(index, count: count))
        }
    }
}

private struct TableHeaderRow: View {
    let columns: [String]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, title in
                Text(title)
                    .modifier(TableCell(index: index, count: columns.count))
            }
        }
        .font(AppFont.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }
}

private struct TableDataRow: View {
    let cells: [String]
    var lastColor: Color = .primary
    var isMuted = false

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, text in
                Text(text)
                    .foregroundStyle(index == cells.count - 1 ? lastColor : (isMuted ? Color.secondary : Color.primary))
                    .modifier(TableCell(index: index, count: cells.count))
            }
        }
        .font(AppFont.body.monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(isHovered ? Color.primary.opacity(0.025) : .clear)
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline.opacity(0.7)).frame(height: 1)
        }
    }
}

private struct CarryOverPopover: View {
    let job: Job

    var body: some View {
        SettingsSection(title: "Carry-over for \(job.displayName)", footer: CarryOverText.footer) {
            CarryOverFields(job: job)
        }
        .padding(16)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.canvas)
    }
}
