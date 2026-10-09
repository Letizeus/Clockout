import AppIntents
import Foundation

/// A job as Shortcuts and Siri see it.
struct JobEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Job"
    static let defaultQuery = JobEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct JobEntityQuery: EntityQuery {
    @Dependency private var jobs: JobStore

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [JobEntity] {
        jobs.jobs.filter { identifiers.contains($0.uuid) }.map { JobEntity(id: $0.uuid, name: $0.displayName) }
    }

    @MainActor
    func suggestedEntities() async throws -> [JobEntity] {
        jobs.jobs.map { JobEntity(id: $0.uuid, name: $0.displayName) }
    }
}

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer"
    static let description = IntentDescription("Starts or resumes time tracking. If another job is running, it is ended.")

    @Parameter(title: "Job", description: "Leave empty for the last selected job.")
    var job: JobEntity?

    @Dependency private var tracker: TimeTracker

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = job.flatMap { tracker.jobs.job(withID: $0.id) } ?? tracker.focusJob
        tracker.start(job: target)
        return .result(dialog: "Timer for \(target.displayName) is running.")
    }
}

struct PauseTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Take a Break"
    static let description = IntentDescription("Pauses the running timer.")

    @Dependency private var tracker: TimeTracker

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard tracker.status == .working else { return .result(dialog: "No timer is running.") }
        tracker.pause()
        return .result(dialog: "Break started.")
    }
}

struct StopTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish Day"
    static let description = IntentDescription("Ends the working day.")

    @Dependency private var tracker: TimeTracker

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard tracker.status != .idle else { return .result(dialog: "No timer is running.") }
        let job = tracker.focusJob
        tracker.stop()
        let worked = tracker.report(forDayOf: .now, job: job, now: .now).workedDuration
        return .result(dialog: "Done for today: \(worked.clock) hours for \(job.displayName).")
    }
}

struct TodayWorkedIntent: AppIntent {
    static let title: LocalizedStringResource = "Hours Worked Today"
    static let description = IntentDescription("Tells you how long you have worked today.")

    @Dependency private var tracker: TimeTracker

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let job = tracker.focusJob
        let worked = tracker.report(forDayOf: .now, job: job, now: .now).workedDuration
        let target = job.rules.plannedTarget(for: .now)
        let text = target > 0
            ? String(localized: "\(worked.clock) of \(target.clock) hours for \(job.displayName) today.")
            : String(localized: "\(worked.clock) hours for \(job.displayName) today.")
        return .result(value: "\(worked.clock) h", dialog: "\(text)")
    }
}

struct WorkingHoursShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start the timer in \(.applicationName)",
                "Start \(.applicationName)",
                "Start \(\.$job) in \(.applicationName)",
            ],
            shortTitle: "Start Timer",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PauseTimerIntent(),
            phrases: ["Take a break in \(.applicationName)", "Pause \(.applicationName)"],
            shortTitle: "Break",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: StopTimerIntent(),
            phrases: ["Finish the day in \(.applicationName)", "End the workday in \(.applicationName)"],
            shortTitle: "Finish Day",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: TodayWorkedIntent(),
            phrases: ["How long did I work today in \(.applicationName)", "Hours worked today in \(.applicationName)"],
            shortTitle: "Worked Today",
            systemImageName: "clock"
        )
    }
}
