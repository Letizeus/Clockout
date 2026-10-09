import AppKit
import Foundation
import SwiftData
import Testing
@testable import Clockout

@MainActor
struct BackupTests {
    private struct Setup {
        let container: ModelContainer
        let jobs: JobStore
        let tracker: TimeTracker
    }

    private func makeSetup(_ name: String) throws -> Setup {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let container = try ModelContainer(for: WorkSession.self, Job.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let jobs = JobStore(context: container.mainContext, defaults: defaults)
        let tracker = TimeTracker(context: container.mainContext, settings: AppSettings(defaults: defaults), jobs: jobs, defaults: defaults)
        return Setup(container: container, jobs: jobs, tracker: tracker)
    }

    private func pngIcon() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func restoresEverythingIntoAnotherStore() throws {
        let source = try makeSetup("backup-source-tests")
        let main = source.jobs.currentJob
        main.name = "Werkstudent"
        main.targetMode = .weekly
        main.weeklyTargetMinutes = 8 * 60
        main.startDate = Calendar.app.date(from: DateComponents(year: 2026, month: 3, day: 1))
        main.balanceCarryOverMinutes = -90
        main.balanceCarryOverDate = Calendar.app.date(from: DateComponents(year: 2026, month: 1, day: 1))
        main.holidayRegion = HolidayRegion(country: .germany, state: .bavaria)
        main.ignoredHolidays = [.assumption]
        main.setAbsence(.vacation, on: [Calendar.app.date(from: DateComponents(year: 2026, month: 8, day: 3))!])
        main.iconData = pngIcon()
        let second = source.jobs.addJob(name: "Café", color: .orange)
        source.jobs.select(second)

        let start = Date.now.addingTimeInterval(-7200)
        source.container.mainContext.insert(WorkSession(start: start, end: start.addingTimeInterval(3600), note: "Sprint", jobID: main.uuid))
        source.container.mainContext.insert(WorkSession(start: start.addingTimeInterval(3700), end: nil, jobID: second.uuid))
        try source.container.mainContext.save()

        let sessions = try source.container.mainContext.fetch(FetchDescriptor<WorkSession>())
        let data = try Backup(jobs: source.jobs.jobs, sessions: sessions, currentJobID: second.uuid).encoded()

        let target = try makeSetup("backup-target-tests")
        target.container.mainContext.insert(WorkSession(start: .now.addingTimeInterval(-60), end: .now, jobID: target.jobs.currentJob.uuid))
        try Backup.decode(data).restore(into: target.container.mainContext, tracker: target.tracker, jobStore: target.jobs)

        #expect(target.jobs.jobs.map(\.name) == ["Werkstudent", "Café"])
        #expect(target.jobs.currentJob.uuid == second.uuid)
        let restored = try #require(target.jobs.job(withID: main.uuid))
        #expect(restored.targetMode == .weekly)
        #expect(restored.weeklyTargetMinutes == 8 * 60)
        #expect(restored.startDate == main.startDate)
        #expect(restored.carryOver == main.carryOver)
        #expect(restored.holidayRegion == HolidayRegion(country: .germany, state: .bavaria))
        #expect(restored.ignoredHolidays == [.assumption])
        #expect(restored.absences == main.absences)
        #expect(restored.iconData != nil)

        let restoredSessions = try target.container.mainContext.fetch(FetchDescriptor<WorkSession>(sortBy: [SortDescriptor(\.start)]))
        #expect(restoredSessions.count == 2)
        #expect(restoredSessions[0].note == "Sprint")
        #expect(restoredSessions[0].jobID == main.uuid)
        #expect(target.tracker.runningSession?.jobID == second.uuid)
        withExtendedLifetime(source.container) {}
    }

    @Test func refusesFilesThatAreNoBackup() throws {
        #expect(throws: Backup.ReadError.notABackup) { try Backup.decode(Data("{}".utf8)) }
        #expect(throws: Backup.ReadError.notABackup) { try Backup.decode(Data("kein json".utf8)) }

        let source = try makeSetup("backup-version-tests")
        var backup = Backup(jobs: source.jobs.jobs, sessions: [], currentJobID: nil)
        backup.version = Backup.currentVersion + 1
        #expect(throws: Backup.ReadError.newerVersion) { try Backup.decode(backup.encoded()) }
        withExtendedLifetime(source.container) {}
    }
}
