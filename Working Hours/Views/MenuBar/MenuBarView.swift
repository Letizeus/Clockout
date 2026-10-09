import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let tracker: TimeTracker

    var body: some View {
        switch tracker.status {
        case .idle:
            Image(systemName: "clock")
        case .working:
            let worked = tracker.report(forDayOf: tracker.now, job: tracker.focusJob, now: tracker.now).workedDuration
            Text("\(Image(systemName: "timer")) \(worked.clock)")
                .monospacedDigit()
        case .onBreak:
            Text("\(Image(systemName: "cup.and.saucer.fill")) \(tracker.currentBreakDuration.clock)")
                .monospacedDigit()
        }
    }
}

struct MenuBarView: View {
    @Environment(JobStore.self) private var jobs

    var body: some View {
        let job = jobs.currentJob
        TimelineView(.everyMinute) { context in
            let day = Calendar.app.startOfDay(for: context.date)
            DaySessionsQuery(day: day, job: job) { sessions in
                MenuBarContent(job: job, sessions: sessions)
            }
            .id("\(job.uuid)-\(day.timeIntervalSince1970)")
        }
    }
}

private struct MenuBarContent: View {
    let job: Job
    let sessions: [WorkSession]

    @Environment(TimeTracker.self) private var tracker
    @Environment(JobStore.self) private var jobs
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let now = tracker.now
        let status = tracker.status(for: job)
        let report = DayReport(sessions: sessions, now: now)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    JobIcon(job: job, size: 20)
                    if jobs.jobs.count > 1 {
                        Picker("Job", selection: Binding(get: { job.uuid }, set: { id in
                            if let selected = jobs.job(withID: id) { jobs.select(selected) }
                        })) {
                            ForEach(jobs.jobs, id: \.uuid) { job in
                                Text(job.displayName).tag(job.uuid)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .buttonStyle(.borderless)
                        .fixedSize()
                    } else {
                        Text(job.displayName)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Spacer()
                    StatusBadge(status: status)
                }

                if let active = tracker.activeJob, active !== job {
                    Button {
                        jobs.select(active)
                    } label: {
                        HStack(spacing: 6) {
                            JobIcon(job: active, size: 14)
                            Text("\(active.displayName) is running")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Show")
                                .foregroundStyle(Color.brand)
                        }
                        .font(AppFont.label)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                AwayBanner(isCompact: true)
                UpdateBanner(isCompact: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(report.workedDuration.stopwatch)
                        .font(.system(size: 34, weight: .medium).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(phaseText(status: status, report: report))
                        .font(AppFont.label)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TimerActionButton(status: status, title: tracker.primaryActionTitle(for: job), fillsWidth: true) {
                        tracker.togglePrimary(for: job)
                    }

                    Button {
                        tracker.stop()
                    } label: {
                        Label("Finish Day", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondary(height: 32))
                    .disabled(status == .idle)
                }
            }
            .padding(14)

            if let entry = TimesheetEntry(report: report, roundingMinutes: job.roundingMinutes) {
                MenuDivider()
                timesheetSummary(entry)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            if !sessions.isEmpty {
                MenuDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Work blocks today")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                    ForEach(sessions.suffix(5)) { session in
                        HStack {
                            Text(session.end.map { String(localized: "\(session.start.clockTime) to \($0.clockTime)") } ?? String(localized: "\(session.start.clockTime) until now"))
                            Spacer()
                            Text("\(session.duration(now: now).clock) h")
                                .foregroundStyle(.secondary)
                        }
                        .font(AppFont.body.monospacedDigit())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            MenuDivider()

            HStack(spacing: 2) {
                Button("Open Window") {
                    openWindow(id: WindowID.main)
                    MenuBarMode.showApp()
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    MenuBarMode.quit()
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Working Hours. A running timer keeps counting.")
            }
            .buttonStyle(.ghost)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 320)
    }

    private func timesheetSummary(_ entry: TimesheetEntry) -> some View {
        let pause = job.breakFormat.strings(for: entry.breakDuration)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("For the timesheet")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                Text("\(entry.start.clockTime) to \(entry.end.clockTime), break \(pause.display)")
                    .font(AppFont.body.monospacedDigit())
            }
            Spacer()
            CopyButton(
                value: [entry.start.clockTime, entry.end.clockTime, pause.copy].joined(separator: "\t"),
                help: "Copy start, end and break"
            )
        }
    }

    private func phaseText(status: TimeTracker.Status, report: DayReport) -> String {
        switch status {
        case .working:
            return String(localized: "Current block: \(tracker.currentBlockDuration.stopwatch)")
        case .onBreak:
            return String(localized: "Break since \(tracker.breakStartedAt?.clockTime ?? ""): \(tracker.currentBreakDuration.stopwatch)")
        case .idle:
            if let lastEnd = report.lastEnd {
                return String(localized: "Worked today, last until \(lastEnd.clockTime)")
            }
            return String(localized: "Not started today")
        }
    }
}

private struct MenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
    }
}
