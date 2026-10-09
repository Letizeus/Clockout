import Foundation
import SwiftData
import Testing
@testable import Clockout

@MainActor
struct AwayTests {
    private func makeTracker(_ name: String) throws -> (TimeTracker, Job, ModelContainer) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let container = try ModelContainer(for: WorkSession.self, Job.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let jobs = JobStore(context: container.mainContext, defaults: defaults)
        let tracker = TimeTracker(context: container.mainContext, settings: AppSettings(defaults: defaults), jobs: jobs, defaults: defaults)
        return (tracker, jobs.currentJob, container)
    }

    @Test func awayTimeBecomesABreak() throws {
        let (tracker, job, container) = try makeTracker("away-break-tests")
        let start = Date.now.addingTimeInterval(-3 * 3600)
        tracker.start(job: job, at: start)
        tracker.reportAway(DateInterval(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(6000)))
        tracker.takeAwayAsBreak()

        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>(sortBy: [SortDescriptor(\.start)]))
        #expect(sessions.count == 2)
        #expect(sessions[0].end == start.addingTimeInterval(3600))
        #expect(sessions[1].start == start.addingTimeInterval(6000))
        #expect(sessions[1].end == nil)
        #expect(tracker.awayPeriod == nil)
    }

    @Test func awayTimeCanEndTheDay() throws {
        let (tracker, job, container) = try makeTracker("away-stop-tests")
        let start = Date.now.addingTimeInterval(-2 * 3600)
        tracker.start(job: job, at: start)
        tracker.reportAway(DateInterval(start: start.addingTimeInterval(1800), end: start.addingTimeInterval(5400)))
        tracker.stopAtAwayStart()

        let sessions = try container.mainContext.fetch(FetchDescriptor<WorkSession>())
        #expect(sessions.count == 1)
        #expect(sessions[0].end == start.addingTimeInterval(1800))
        #expect(tracker.status == .idle)
    }

    @Test func awayIsOnlyKeptWhileTheTimerRuns() throws {
        let (tracker, job, container) = try makeTracker("away-idle-tests")
        tracker.reportAway(DateInterval(start: .now.addingTimeInterval(-1800), end: .now))
        #expect(tracker.awayPeriod == nil)

        let start = Date.now.addingTimeInterval(-3600)
        tracker.start(job: job, at: start)
        // Starts before the block are cut to the block, a second absence extends the first.
        tracker.reportAway(DateInterval(start: start.addingTimeInterval(-600), end: start.addingTimeInterval(900)))
        tracker.reportAway(DateInterval(start: start.addingTimeInterval(1200), end: start.addingTimeInterval(2400)))
        #expect(tracker.awayPeriod == DateInterval(start: start, end: start.addingTimeInterval(2400)))

        tracker.pause()
        #expect(tracker.awayPeriod == nil)
        // The job is only valid while its container exists.
        withExtendedLifetime(container) {}
    }
}
