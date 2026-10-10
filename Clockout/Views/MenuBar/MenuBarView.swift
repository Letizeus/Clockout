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
            item(symbol: "timer", time: worked)
        case .onBreak:
            item(symbol: "cup.and.saucer.fill", time: tracker.currentBreakDuration)
        }
    }

    /// The menu bar drops images embedded in text, so the symbol and the time are separate views.
    private func item(symbol: String, time: TimeInterval) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(time.clock)
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
            VStack(alignment: .leading, spacing: 16) {
                header(status: status)
                otherJobNotice
                AwayBanner(isCompact: true)
                UpdateBanner(isCompact: true)
                hero(status: status, report: report, goal: TargetProgress(job: job, report: report, now: now))
                actions(status: status)
            }
            .padding(16)

            if !sessions.isEmpty {
                MenuDivider()
                blocks(report: report, now: now)
                    .padding(16)
            }

            if let entry = TimesheetEntry(report: report, roundingMinutes: job.roundingMinutes) {
                MenuDivider()
                timesheet(entry)
                    .padding(16)
            }

            MenuDivider()
            footer
        }
        .frame(width: 320)
        .animation(.smooth, value: status)
    }

    // MARK: Sections

    private func header(status: TimeTracker.Status) -> some View {
        HStack(spacing: 8) {
            if jobs.jobs.count > 1 {
                Menu {
                    Picker("Job", selection: Binding(get: { job.uuid }, set: { id in
                        if let selected = jobs.job(withID: id) { jobs.select(selected) }
                    })) {
                        ForEach(jobs.jobs, id: \.uuid) { job in
                            Text(job.displayName).tag(job.uuid)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    jobTitle(showsChevron: true)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            } else {
                jobTitle(showsChevron: false)
            }
            Spacer(minLength: 8)
            StatusBadge(status: status)
        }
    }

    private func jobTitle(showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            JobIcon(job: job, size: 22)
            Text(job.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var otherJobNotice: some View {
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
    }

    private func hero(status: TimeTracker.Status, report: DayReport, goal: TargetProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.workedDuration.stopwatch)
                    .font(.system(size: 38, weight: .medium).monospacedDigit())
                    .contentTransition(.numericText())
                Text(phaseText(status: status, report: report))
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                if goal.target > 0 {
                    HStack(spacing: 10) {
                        ProgressBar(progress: goal.progress, tint: status == .onBreak ? .amber : .brand)
                        Text(verbatim: goal.progress.formatted(.percent.precision(.fractionLength(0)).locale(.app)))
                            .font(AppFont.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(goal.summary(for: status))
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actions(status: TimeTracker.Status) -> some View {
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

    private func blocks(report: DayReport, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Work blocks today")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)

            DayStrip(report: report)

            VStack(spacing: 7) {
                ForEach(sessions.suffix(4)) { session in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(session.isRunning ? Color.brand : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(session.end.map { String(localized: "\(session.start.clockTime) to \($0.clockTime)") } ?? String(localized: "\(session.start.clockTime) until now"))
                            .fixedSize()
                        if !session.note.isEmpty {
                            Text(session.note)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("\(session.duration(now: now).clock) h")
                            .foregroundStyle(session.isRunning ? Color.brand : Color.secondary)
                    }
                    .font(AppFont.body.monospacedDigit())
                }
            }
        }
    }

    private func timesheet(_ entry: TimesheetEntry) -> some View {
        let pause = job.breakFormat.strings(for: entry.breakDuration)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("For the timesheet")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(
                    value: [entry.start.clockTime, entry.end.clockTime, pause.copy].joined(separator: "\t"),
                    help: "Copy start, end and break"
                )
                .padding(.vertical, -6)
            }

            HStack(spacing: 0) {
                timesheetField("Start time", value: entry.start.clockTime)
                FieldSeparator()
                timesheetField("End time", value: entry.end.clockTime)
                FieldSeparator()
                timesheetField("Break", value: pause.display)
            }
            .padding(.vertical, 9)
            .background(Color.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.hairline)
            }
        }
    }

    private func timesheetField(_ title: LocalizedStringResource, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Button {
                openWindow(id: WindowID.main)
                MenuBarMode.showApp()
            } label: {
                Label("Open Window", systemImage: "macwindow")
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
            .help("Quit (timer keeps running)")
        }
        .buttonStyle(.ghost)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
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

/// Thin bar toward the day's target.
private struct ProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.hairline)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
        }
        .frame(height: 6)
        .animation(.smooth, value: progress)
    }
}

/// The day from first start to last end: work blocks filled, breaks left empty.
private struct DayStrip: View {
    let report: DayReport

    var body: some View {
        GeometryReader { proxy in
            if let start = report.firstStart, let end = report.lastEnd, end > start {
                let span = end.timeIntervalSince(start)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.hairline.opacity(0.6))
                    ForEach(report.workIntervals, id: \.self) { interval in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.brand)
                            .frame(width: max(2, proxy.size.width * interval.duration / span))
                            .offset(x: proxy.size.width * interval.start.timeIntervalSince(start) / span)
                    }
                }
            }
        }
        .frame(height: 8)
    }
}

private struct FieldSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(width: 1, height: 26)
    }
}

private struct MenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
    }
}
