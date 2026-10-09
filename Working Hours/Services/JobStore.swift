import Foundation
import Observation
import OSLog
import SwiftData

/// The list of jobs and which one is shown. There is always at least one job.
@Observable
final class JobStore {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: "WorkingHours", category: "JobStore")

    private(set) var jobs: [Job] = []
    private(set) var currentJob: Job

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults

        let descriptor = FetchDescriptor<Job>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)])
        var loaded = (try? context.fetch(descriptor)) ?? []
        if loaded.isEmpty {
            let job = Self.makeFirstJob(from: defaults)
            context.insert(job)
            loaded = [job]
        }
        jobs = loaded

        let savedID = defaults.string(forKey: AppSettings.Key.currentJobID).flatMap(UUID.init(uuidString:))
        currentJob = loaded.first { $0.uuid == savedID } ?? loaded[0]

        adoptOrphanedSessions()
        save()
    }

    func job(withID id: UUID?) -> Job? {
        guard let id else { return nil }
        return jobs.first { $0.uuid == id }
    }

    func select(_ job: Job) {
        guard jobs.contains(where: { $0 === job }) else { return }
        currentJob = job
        defaults.set(job.uuid.uuidString, forKey: AppSettings.Key.currentJobID)
    }

    @discardableResult
    func addJob(name: String, color: JobColor, copyingRulesFrom template: Job? = nil) -> Job {
        let job = Job(name: name, color: color, sortIndex: (jobs.map(\.sortIndex).max() ?? -1) + 1)
        if let template { job.copyRules(from: template) }
        context.insert(job)
        jobs.append(job)
        save()
        return job
    }

    /// Removes the job from the list. Its sessions are deleted by `TimeTracker.deleteJob(_:)`.
    func remove(_ job: Job) {
        guard jobs.count > 1, let index = jobs.firstIndex(where: { $0 === job }) else { return }
        jobs.remove(at: index)
        if currentJob === job {
            select(jobs[min(index, jobs.count - 1)])
        }
        context.delete(job)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { jobs[$0] }
        var reordered = jobs.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        reordered.insert(contentsOf: moving, at: destination - source.filter { $0 < destination }.count)
        jobs = reordered
        for (index, job) in jobs.enumerated() {
            job.sortIndex = index
        }
        save()
    }

    /// After restoring a backup. The old jobs must already be deleted from the context.
    func replaceAll(with newJobs: [Job], selecting id: UUID?) {
        guard !newJobs.isEmpty else { return }
        jobs = newJobs.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
        select(jobs.first { $0.uuid == id } ?? jobs[0])
        save()
    }

    /// A color not used yet, for new jobs.
    var nextColor: JobColor {
        let used = Set(jobs.map(\.color))
        return JobColor.allCases.first { !used.contains($0) && $0 != .gray } ?? .gray
    }

    func save() {
        do {
            try context.save()
        } catch {
            logger.error("Saving jobs failed: \(error.localizedDescription)")
        }
    }

    // MARK: Migration

    /// The first job takes over the rules that used to be global settings.
    private static func makeFirstJob(from defaults: UserDefaults) -> Job {
        typealias Key = AppSettings.LegacyKey
        let job = Job(name: String(localized: "Main job"), color: .blue)
        if let mode = defaults.string(forKey: Key.targetMode).flatMap(TargetMode.init(rawValue:)) {
            job.targetMode = mode
        }
        if let minutes = defaults.object(forKey: Key.dailyTargetMinutes) as? Int {
            job.dailyTargetMinutes = minutes
        }
        if let minutes = defaults.object(forKey: Key.weeklyTargetMinutes) as? Int {
            job.weeklyTargetMinutes = minutes
        }
        if let workdays = defaults.array(forKey: Key.workdays) as? [Int] {
            job.workdayList = workdays.sorted()
        }
        if let rounding = defaults.object(forKey: Key.roundingMinutes) as? Int {
            job.roundingMinutes = rounding
        }
        if let trackedOnly = defaults.object(forKey: Key.targetOnlyOnTrackedDays) as? Bool {
            job.targetOnlyOnTrackedDays = trackedOnly
        }
        if let format = defaults.string(forKey: Key.breakFormat).flatMap(BreakFormat.init(rawValue:)) {
            job.breakFormat = format
        }
        return job
    }

    /// Sessions recorded before jobs existed belong to the job that is shown.
    private func adoptOrphanedSessions() {
        let descriptor = FetchDescriptor<WorkSession>(predicate: #Predicate { $0.jobID == nil })
        guard let orphans = try? context.fetch(descriptor), !orphans.isEmpty else { return }
        for session in orphans {
            session.jobID = currentJob.uuid
        }
        logger.info("Assigned \(orphans.count) sessions to \(self.currentJob.displayName)")
    }
}
