import Foundation
import Observation
import OSLog
import SwiftData

/// Drives the timer: starting, pausing and finishing work blocks.
///
/// Only one block runs at a time. Starting a different job ends the running block, so
/// switching from one job to the other is a single click. The running block is stored with
/// `end == nil`, so tracking survives quitting the app.
@Observable
final class TimeTracker {
    enum Status {
        case idle
        case working
        case onBreak
    }

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: "Clockout", category: "TimeTracker")
    @ObservationIgnored private var ticker: Timer?

    let jobs: JobStore
    private(set) var runningSession: WorkSession?
    /// Updated every second so live displays (menu bar, timers) stay current.
    private(set) var now = Date()
    private(set) var breakStartedAt: Date? {
        didSet { defaults.set(breakStartedAt, forKey: AppSettings.Key.breakStartedAt) }
    }
    private(set) var breakJobID: UUID? {
        didSet { defaults.set(breakJobID?.uuidString, forKey: AppSettings.Key.breakJobID) }
    }
    /// Time nobody used the Mac while the timer ran, waiting for the user to decide. See `AwayDetector`.
    private(set) var awayPeriod: DateInterval?

    init(context: ModelContext, settings: AppSettings, jobs: JobStore, defaults: UserDefaults = .standard) {
        self.context = context
        self.settings = settings
        self.jobs = jobs
        self.defaults = defaults
        breakStartedAt = defaults.object(forKey: AppSettings.Key.breakStartedAt) as? Date
        breakJobID = defaults.string(forKey: AppSettings.Key.breakJobID).flatMap(UUID.init(uuidString:))
        reloadRunningSession()
        startTicking()
    }

    // MARK: Status

    /// Across all jobs.
    var status: Status {
        if runningSession != nil { return .working }
        if isOnBreakToday { return .onBreak }
        return .idle
    }

    func status(for job: Job) -> Status {
        if let runningSession { return runningSession.jobID == job.uuid ? .working : .idle }
        if isOnBreakToday && breakJobID == job.uuid { return .onBreak }
        return .idle
    }

    /// The job that is working or on a break right now.
    var activeJob: Job? {
        if let runningSession { return jobs.job(withID: runningSession.jobID) }
        if isOnBreakToday { return jobs.job(withID: breakJobID) }
        return nil
    }

    /// The job the menu bar and keyboard shortcuts act on.
    var focusJob: Job { activeJob ?? jobs.currentJob }

    func primaryActionTitle(for job: Job) -> String {
        switch status(for: job) {
        case .idle: String(localized: "Start")
        case .working: String(localized: "Pause")
        case .onBreak: String(localized: "Resume")
        }
    }

    private var isOnBreakToday: Bool {
        guard let breakStartedAt else { return false }
        return Calendar.app.isDate(breakStartedAt, inSameDayAs: now)
    }

    // MARK: Actions

    func togglePrimary(for job: Job) {
        status(for: job) == .working ? pause() : start(job: job)
    }

    func togglePrimary() {
        togglePrimary(for: focusJob)
    }

    func start(job: Job, at date: Date = .now) {
        awayPeriod = nil
        if let runningSession {
            guard runningSession.jobID != job.uuid else { return }
            finishRunningSession(at: date)
        }
        let workedBefore = report(forDayOf: date, job: job, now: date).workedDuration
        let session = WorkSession(start: date, jobID: job.uuid)
        context.insert(session)
        runningSession = session
        breakStartedAt = nil
        breakJobID = nil
        save()
        ReminderScheduler.scheduleForWorkBlock(starting: date, workedBefore: workedBefore, job: job, settings: settings)
    }

    func pause(at date: Date = .now) {
        awayPeriod = nil
        let jobID = runningSession?.jobID
        guard finishRunningSession(at: date) else { return }
        breakStartedAt = date
        breakJobID = jobID
    }

    /// Ends the working day. Starting again later the same day simply adds another block.
    func stop(at date: Date = .now) {
        awayPeriod = nil
        finishRunningSession(at: date)
        breakStartedAt = nil
        breakJobID = nil
    }

    // MARK: Away

    /// Keeps the period for the user to decide, as long as the timer still runs.
    func reportAway(_ interval: DateInterval) {
        guard let runningSession else { return }
        let start = max(interval.start, runningSession.start)
        guard interval.end > start else { return }
        // A second absence before the decision extends the first one.
        let begin = min(awayPeriod?.start ?? start, start)
        awayPeriod = DateInterval(start: begin, end: interval.end)
    }

    /// Ends the running block when the absence began and starts a new one when it ended.
    func takeAwayAsBreak() {
        guard let away = awayPeriod, let session = runningSession, let job = jobs.job(withID: session.jobID) else {
            awayPeriod = nil
            return
        }
        finishRunningSession(at: away.start)
        start(job: job, at: min(away.end, .now))
    }

    /// The work day ended when the absence began.
    func stopAtAwayStart() {
        guard let away = awayPeriod else { return }
        stop(at: away.start)
    }

    func dismissAway() {
        awayPeriod = nil
    }

    func delete(_ session: WorkSession) {
        if session === runningSession {
            runningSession = nil
            ReminderScheduler.cancelWorkBlockReminders()
        }
        context.delete(session)
        save()
    }

    /// Deletes the job together with all of its entries.
    func deleteJob(_ job: Job) {
        guard jobs.jobs.count > 1 else { return }
        if runningSession?.jobID == job.uuid {
            runningSession = nil
            ReminderScheduler.cancelWorkBlockReminders()
        }
        if breakJobID == job.uuid {
            breakStartedAt = nil
            breakJobID = nil
        }
        for session in sessions(of: job) {
            context.delete(session)
        }
        jobs.remove(job)
        save()
    }

    /// Deletes every entry and absence of every job. The jobs and their rules stay.
    func deleteAllData() {
        do {
            for session in try context.fetch(FetchDescriptor<WorkSession>()) {
                context.delete(session)
            }
            for job in jobs.jobs {
                job.absences = []
            }
        } catch {
            logger.error("Fetching sessions for deletion failed: \(error.localizedDescription)")
        }
        runningSession = nil
        breakStartedAt = nil
        breakJobID = nil
        ReminderScheduler.cancelWorkBlockReminders()
        save()
    }

    func importRows(_ rows: [ImportedRow], into job: Job, strategy: ImportConflictStrategy) -> ImportResult {
        let byDay = Dictionary(grouping: rows.filter(\.isValid)) { $0.day! }
        var result = ImportResult()

        for (day, dayRows) in byDay.sorted(by: { $0.key < $1.key }) {
            let existing = sessions(forDayOf: day, job: job)
            if !existing.isEmpty {
                switch strategy {
                case .skipExistingDays:
                    result.skippedDays += 1
                    continue
                case .replaceExistingDays:
                    for session in existing where !session.isRunning {
                        context.delete(session)
                    }
                    result.replacedDays += 1
                case .add:
                    break
                }
            }
            for row in dayRows {
                for block in row.blocks {
                    context.insert(WorkSession(start: block.start, end: block.end, note: row.note, jobID: job.uuid))
                    result.createdBlocks += 1
                }
            }
            result.importedDays += 1
        }

        save()
        return result
    }

    /// Call after sessions were edited elsewhere, e.g. when the running block got an end time.
    func sessionsDidChange() {
        save()
        let wasRunning = runningSession != nil
        reloadRunningSession()
        if runningSession == nil { awayPeriod = nil }
        if wasRunning && runningSession == nil {
            ReminderScheduler.cancelWorkBlockReminders()
        }
    }

    func rescheduleReminders() {
        ReminderScheduler.cancelWorkBlockReminders()
        guard let runningSession, let job = jobs.job(withID: runningSession.jobID) else { return }
        let workedBefore = report(forDayOf: runningSession.start, job: job, now: now).workedDuration - currentBlockDuration
        ReminderScheduler.scheduleForWorkBlock(
            starting: runningSession.start,
            workedBefore: max(0, workedBefore),
            job: job,
            settings: settings
        )
    }

    // MARK: Queries

    var currentBlockDuration: TimeInterval {
        runningSession?.duration(now: now) ?? 0
    }

    var currentBreakDuration: TimeInterval {
        guard isOnBreakToday, runningSession == nil, let breakStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(breakStartedAt))
    }

    func sessions(forDayOf day: Date, job: Job) -> [WorkSession] {
        let jobID: UUID? = job.uuid
        let start = Calendar.app.startOfDay(for: day)
        let end = Calendar.app.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return fetch(FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.jobID == jobID && $0.start >= start && $0.start < end },
            sortBy: [SortDescriptor(\.start)]
        ))
    }

    func sessions(of job: Job) -> [WorkSession] {
        let jobID: UUID? = job.uuid
        return fetch(FetchDescriptor<WorkSession>(predicate: #Predicate { $0.jobID == jobID }))
    }

    func report(forDayOf day: Date, job: Job, now: Date) -> DayReport {
        DayReport(sessions: sessions(forDayOf: day, job: job), now: now)
    }

    func save() {
        do {
            try context.save()
        } catch {
            logger.error("Saving failed: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    private func fetch(_ descriptor: FetchDescriptor<WorkSession>) -> [WorkSession] {
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Fetching sessions failed: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    private func finishRunningSession(at date: Date) -> Bool {
        guard let session = runningSession else { return false }
        session.end = max(date, session.start)
        runningSession = nil
        save()
        ReminderScheduler.cancelWorkBlockReminders()
        return true
    }

    private func reloadRunningSession() {
        var descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.end == nil },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        runningSession = (try? context.fetch(descriptor))?.first
    }

    private func startTicking() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = .now
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
}
