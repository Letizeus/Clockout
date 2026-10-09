import SwiftUI

struct TodayView: View {
    @Environment(JobStore.self) private var jobs

    var body: some View {
        let job = jobs.currentJob
        TimelineView(.everyMinute) { context in
            let day = Calendar.app.startOfDay(for: context.date)
            DaySessionsQuery(day: day, job: job) { sessions in
                TodayContent(day: day, job: job, sessions: sessions)
            }
            .id("\(job.uuid)-\(day.timeIntervalSince1970)")
            .navigationTitle("Today")
            .navigationSubtitle(day.dayTitle)
        }
    }
}

private struct TodayContent: View {
    let day: Date
    let job: Job
    let sessions: [WorkSession]

    @Environment(TimeTracker.self) private var tracker
    @State private var editorTarget: SessionEditorTarget?

    var body: some View {
        let now = tracker.now
        let report = DayReport(sessions: sessions, now: now)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OtherJobRunningBanner(job: job)
                AwayBanner()
                UpdateBanner()
                if let running = tracker.runningSession, running.jobID == job.uuid, running.start < day {
                    StaleSessionBanner(session: running) {
                        editorTarget = .edit(running)
                    }
                }
                TimerHeroView(job: job, report: report, now: now)
                DayOverview(day: day, job: job, sessions: sessions, report: report, now: now)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
            .overlayScrollers()
        }
        .sheet(item: $editorTarget) { SessionEditorView(target: $0) }
    }
}

/// Shown when the timer was left running overnight.
private struct StaleSessionBanner: View {
    let session: WorkSession
    let onFix: () -> Void

    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("The timer has been running since \(session.start.shortDayTitle), \(session.start.clockTime)")
                    .font(AppFont.bodyMedium)
                Text("Did you forget to stop it? Set the actual end.")
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Set End…", action: onFix)
                .buttonStyle(.secondary(height: 28))
        }
        .card(padding: 12)
    }
}

struct TimerHeroView: View {
    let job: Job
    let report: DayReport
    let now: Date

    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        let status = tracker.status(for: job)
        let target = job.rules.plannedTarget(for: now)
        let progress = target > 0 ? report.workedDuration / target : 0

        HStack(alignment: .center, spacing: 22) {
            ProgressRing(progress: progress, tint: status == .onBreak ? .amber : .brand, lineWidth: 6)
                .overlay {
                    VStack(spacing: 1) {
                        Text(target > 0 ? "\(Int((progress * 100).rounded()))%" : "-")
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        Text("of target")
                            .font(AppFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                StatusBadge(status: status)
                Text(report.workedDuration.stopwatch)
                    .font(AppFont.display)
                    .contentTransition(.numericText())
                Text(targetLine(target: target, status: status))
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 14) {
                phaseInfo(status: status)
                HStack(spacing: 8) {
                    Button {
                        if status != .idle { tracker.stop() }
                    } label: {
                        Label("Finish Day", systemImage: "stop.fill")
                            .fixedSize()
                    }
                    .buttonStyle(.secondary(height: 34))
                    .disabled(status == .idle)
                    .help("End the working day (⇧⌘E)")

                    TimerActionButton(status: status, title: tracker.primaryActionTitle(for: job), height: 34) {
                        tracker.togglePrimary(for: job)
                    }
                    .help("\(tracker.primaryActionTitle(for: job)) (⇧⌘S)")
                }
            }
        }
        .card(padding: 20, cornerRadius: 12)
        .animation(.smooth, value: status)
    }

    private func targetLine(target: TimeInterval, status: TimeTracker.Status) -> String {
        guard target > 0 else {
            if let dayOff = job.dayOff(on: now) { return String(localized: "Today is \(dayOff), no target for \(job.displayName).") }
            return String(localized: "Today is not a workday for \(job.displayName).")
        }
        let remaining = target - report.workedDuration
        guard remaining > 0 else {
            return String(localized: "Target of \(target.clock) h reached, \(remaining.magnitude.clock) h over.")
        }
        if status == .working {
            return String(localized: "Target \(target.clock) h, \(remaining.clock) h to go. Reached at \(now.addingTimeInterval(remaining).clockTime).")
        }
        return String(localized: "Target \(target.clock) h, \(remaining.clock) h left.")
    }

    @ViewBuilder
    private func phaseInfo(status: TimeTracker.Status) -> some View {
        switch status {
        case .working:
            if let session = tracker.runningSession {
                phaseText(title: "Current block since \(session.start.clockTime)", value: tracker.currentBlockDuration.stopwatch)
            }
        case .onBreak:
            phaseText(title: "Break since \(tracker.breakStartedAt?.clockTime ?? "")", value: tracker.currentBreakDuration.stopwatch)
        case .idle:
            if let lastEnd = report.lastEnd {
                phaseText(title: "Last finished", value: lastEnd.clockTime)
            } else {
                phaseText(title: "Not started yet", value: "-")
            }
        }
    }

    private func phaseText(title: LocalizedStringResource, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }
}
