import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \WorkSession.start, order: .reverse) private var allSessions: [WorkSession]
    @Environment(JobStore.self) private var jobs
    @State private var selectedDay: Date? = Calendar.app.startOfDay(for: .now)
    @State private var showsExport = false
    @State private var showsImport = false
    @State private var showsAbsence = false

    private struct DaySummary: Identifiable {
        let day: Date
        let report: DayReport
        let isRunning: Bool
        let absence: AbsenceKind?
        let holiday: String?
        var id: Date { day }
    }

    private struct MonthSection: Identifiable {
        let month: Date
        let days: [DaySummary]
        var id: Date { month }
    }

    private var summaries: [DaySummary] {
        let now = Date.now
        let job = jobs.currentJob
        let jobID = job.uuid
        let rules = job.rules
        let absences = rules.absences
        let byDay = Dictionary(grouping: allSessions.filter { $0.jobID == jobID }) { Calendar.app.startOfDay(for: $0.start) }
        return Set(byDay.keys).union(absences.keys).map { day in
            let items = byDay[day] ?? []
            return DaySummary(
                day: day,
                report: DayReport(sessions: items, now: now),
                isRunning: items.contains(where: \.isRunning),
                absence: absences[day],
                holiday: rules.holiday(on: day)?.title
            )
        }
    }

    private func sections(from summaries: [DaySummary]) -> [MonthSection] {
        let calendar = Calendar.app
        return Dictionary(grouping: summaries) { calendar.dateInterval(of: .month, for: $0.day)?.start ?? $0.day }
            .map { MonthSection(month: $0.key, days: $0.value.sorted { $0.day > $1.day }) }
            .sorted { $0.month > $1.month }
    }

    private var dayBinding: Binding<Date> {
        Binding(
            get: { selectedDay ?? Calendar.app.startOfDay(for: .now) },
            set: { selectedDay = Calendar.app.startOfDay(for: $0) }
        )
    }

    var body: some View {
        let summaries = self.summaries
        let sections = sections(from: summaries)

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                MonthCalendarView(
                    selection: dayBinding,
                    workedByDay: Dictionary(uniqueKeysWithValues: summaries.map { ($0.day, $0.report.workedDuration) }),
                    absenceByDay: jobs.currentJob.rules.absences,
                    holidayTitle: { [rules = jobs.currentJob.rules] in rules.holiday(on: $0)?.title }
                )
                .padding(16)

                Rectangle().fill(Color.hairline).frame(height: 1)

                if sections.isEmpty {
                    VStack(spacing: 12) {
                        EmptyState(
                            systemImage: "calendar",
                            title: "Nothing tracked yet",
                            message: "Tracked days appear here, or import hours from CSV or Excel."
                        )
                        Button("Import Hours…") {
                            showsImport = true
                        }
                        .buttonStyle(.secondary(height: 28))
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                            ForEach(sections) { section in
                                Section {
                                    ForEach(section.days) { summary in
                                        HistoryDayRow(
                                            day: summary.day,
                                            report: summary.report,
                                            isRunning: summary.isRunning,
                                            absence: summary.absence,
                                            holiday: summary.holiday,
                                            isSelected: selectedDay == summary.day
                                        ) {
                                            selectedDay = summary.day
                                        }
                                    }
                                } header: {
                                    Text(section.month.monthTitle)
                                        .font(AppFont.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 12)
                                        .padding(.bottom, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.canvas)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                        .overlayScrollers()
                    }
                }
            }
            .frame(width: 300)
            .frame(maxHeight: .infinity, alignment: .top)

            Rectangle().fill(Color.hairline).frame(width: 1)

            Group {
                if let day = selectedDay {
                    DaySessionsQuery(day: day, job: jobs.currentJob) { sessions in
                        HistoryDayDetail(day: day, job: jobs.currentJob, sessions: sessions)
                    }
                    .id("\(jobs.currentJob.uuid)-\(day.timeIntervalSince1970)")
                } else {
                    EmptyState(systemImage: "calendar", title: "No day selected", message: "Choose a day on the left.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("History")
        .navigationSubtitle(jobs.currentJob.displayName)
        .toolbar {
            ToolbarItem {
                Button("Absence", systemImage: "sun.max") {
                    showsAbsence = true
                }
                .help("Add vacation or sick days")
            }
            ToolbarItem {
                Button("Import", systemImage: "square.and.arrow.down") {
                    showsImport = true
                }
                .help("Import hours from CSV or Excel")
            }
            ToolbarItem {
                Button("Export", systemImage: "square.and.arrow.up") {
                    showsExport = true
                }
                .help("Export as CSV")
            }
        }
        .sheet(isPresented: $showsExport) {
            ExportSheet()
        }
        .sheet(isPresented: $showsImport) {
            ImportSheet()
        }
        .sheet(isPresented: $showsAbsence) {
            AbsenceSheet(job: jobs.currentJob, day: selectedDay ?? Calendar.app.startOfDay(for: .now))
        }
    }
}

private struct HistoryDayRow: View {
    let day: Date
    let report: DayReport
    let isRunning: Bool
    let absence: AbsenceKind?
    let holiday: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.shortDayTitle)
                        .font(AppFont.bodyMedium)
                    Text(rangeText)
                        .font(AppFont.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRunning {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 6, height: 6)
                }
                if let absence {
                    Image(systemName: absence.systemImage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.amber)
                        .help(absence.title)
                } else if let holiday {
                    Image(systemName: "flag")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.amber)
                        .help(holiday)
                }
                if !report.isEmpty || absence == nil {
                    Text("\(report.workedDuration.clock) h")
                        .font(AppFont.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(
                Color.primary.opacity(isSelected ? 0.07 : (isHovered ? 0.035 : 0)),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rangeText: String {
        guard let first = report.firstStart, let last = report.lastEnd else { return absence?.title ?? "-" }
        return isRunning ? String(localized: "\(first.clockTime) until now") : String(localized: "\(first.clockTime) to \(last.clockTime)")
    }
}

private struct HistoryDayDetail: View {
    let day: Date
    let job: Job
    let sessions: [WorkSession]

    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        let now = sessions.contains(where: \.isRunning) ? tracker.now : Date.now
        let report = DayReport(sessions: sessions, now: now)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.dayTitle)
                            .font(.system(size: 18, weight: .semibold))
                        Text(Calendar.app.isDateInToday(day) ? String(localized: "Today") : relativeText)
                            .font(AppFont.body)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AbsenceButton(job: job, day: day)
                        .padding(.trailing, 8)
                    Text("\(report.workedDuration.clock) h")
                        .font(.system(size: 22, weight: .medium).monospacedDigit())
                }
                OtherJobRunningBanner(job: job)
                if let note = noTargetNote {
                    Callout(systemImage: "info.circle", text: "\(note)")
                }
                DayOverview(day: day, job: job, sessions: sessions, report: report, now: now)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
            .overlayScrollers()
        }
    }

    /// Why this workday has no target, if that is not obvious.
    private var noTargetNote: String? {
        if let absence = job.absence(on: day) {
            return String(localized: "\(absence.title): no target; tracked time still counts.")
        }
        if let holiday = job.rules.holiday(on: day) {
            return String(localized: "\(holiday.title): no target; tracked time still counts.")
        }
        if let start = job.startDate, Calendar.app.startOfDay(for: day) < Calendar.app.startOfDay(for: start) {
            return String(localized: "No target before your first day of work (\(start.numericDate)).")
        }
        return nil
    }

    private var relativeText: String {
        let calendar = Calendar.app
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: day).day ?? 0
        switch days {
        case -1: return String(localized: "Yesterday")
        case 1: return String(localized: "Tomorrow")
        case ..<0: return String(localized: "\(-days) days ago")
        default: return String(localized: "In \(days) days")
        }
    }
}
