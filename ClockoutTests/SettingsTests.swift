import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Clockout

@MainActor
struct JobRulesTests {
    @Test func weeklyTargetIsSpreadOverWorkdays() {
        let job = Job(name: "Test")
        job.targetMode = .weekly
        job.weeklyTargetMinutes = 38 * 60 + 30

        #expect(job.dailyTarget == 7 * 3600 + 42 * 60)
        #expect(job.rules.dailyTarget == job.dailyTarget)

        job.workdays = [2, 3, 4, 5]
        #expect(job.dailyTarget.clock == "9:37")
        #expect(job.weeklyTarget.clock == "38:30")

        job.workdays = []
        #expect(job.dailyTarget == 0)
    }

    @Test func switchingModeKeepsTheEffectiveTarget() {
        let job = Job(name: "Test")
        job.dailyTargetMinutes = 7 * 60 + 42

        job.changeTargetMode(to: .weekly)
        #expect(job.weeklyTargetMinutes == 38 * 60 + 30)
        #expect(job.dailyTarget == 7 * 3600 + 42 * 60)

        job.weeklyTargetMinutes = 40 * 60
        job.changeTargetMode(to: .daily)
        #expect(job.dailyTargetMinutes == 8 * 60)
    }

    @Test func parsesTypedDurations() {
        #expect(DurationField.parse("38:30") == 2310)
        #expect(DurationField.parse("38,5") == 2310)
        #expect(DurationField.parse("40") == 2400)
        #expect(DurationField.parse("7:42 h") == 462)
        #expect(DurationField.parse("7:75") == nil)
        #expect(DurationField.parse("abc") == nil)
    }
}

@MainActor
struct JobStoreTests {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: WorkSession.self, Job.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func firstLaunchTurnsOldSettingsAndEntriesIntoAJob() throws {
        let defaults = makeDefaults("job-migration-tests")
        defaults.set("weekly", forKey: AppSettings.LegacyKey.targetMode)
        defaults.set(38 * 60 + 30, forKey: AppSettings.LegacyKey.weeklyTargetMinutes)
        defaults.set([2, 3, 4], forKey: AppSettings.LegacyKey.workdays)
        defaults.set(15, forKey: AppSettings.LegacyKey.roundingMinutes)
        defaults.set("minutes", forKey: AppSettings.LegacyKey.breakFormat)

        let container = try makeContainer()
        let old = WorkSession(start: .now.addingTimeInterval(-3600), end: .now)
        container.mainContext.insert(old)

        let jobs = JobStore(context: container.mainContext, defaults: defaults)
        let job = jobs.currentJob

        #expect(jobs.jobs.count == 1)
        #expect(job.name == "Hauptjob")
        #expect(job.targetMode == .weekly)
        #expect(job.weeklyTargetMinutes == 38 * 60 + 30)
        #expect(job.workdays == [2, 3, 4])
        #expect(job.roundingMinutes == 15)
        #expect(job.breakFormat == .minutes)
        #expect(old.jobID == job.uuid)

        // A second launch keeps the job and the selection.
        let again = JobStore(context: container.mainContext, defaults: defaults)
        #expect(again.jobs.count == 1)
        #expect(again.currentJob.uuid == job.uuid)
    }

    @Test func startingAnotherJobSwitchesTheTimer() throws {
        let defaults = makeDefaults("job-switch-tests")
        let container = try makeContainer()
        let jobs = JobStore(context: container.mainContext, defaults: defaults)
        let tracker = TimeTracker(context: container.mainContext, settings: AppSettings(defaults: defaults), jobs: jobs, defaults: defaults)
        let first = jobs.currentJob
        let second = jobs.addJob(name: "Minijob", color: .orange)

        let start = Date.now.addingTimeInterval(-600)
        tracker.start(job: first, at: start)
        #expect(tracker.status(for: first) == .working)
        #expect(tracker.status(for: second) == .idle)

        tracker.start(job: second, at: start.addingTimeInterval(300))
        #expect(tracker.status(for: first) == .idle)
        #expect(tracker.status(for: second) == .working)
        #expect(tracker.activeJob === second)

        let firstBlocks = tracker.sessions(of: first)
        #expect(firstBlocks.count == 1)
        #expect(firstBlocks.first?.end == start.addingTimeInterval(300))

        tracker.pause(at: start.addingTimeInterval(400))
        #expect(tracker.status(for: second) == .onBreak)
        #expect(tracker.status(for: first) == .idle)
        #expect(tracker.focusJob === second)

        tracker.stop()
        #expect(tracker.status == .idle)
    }

    @Test func deletingAJobRemovesItsEntriesOnly() throws {
        let defaults = makeDefaults("job-delete-tests")
        let container = try makeContainer()
        let jobs = JobStore(context: container.mainContext, defaults: defaults)
        let tracker = TimeTracker(context: container.mainContext, settings: AppSettings(defaults: defaults), jobs: jobs, defaults: defaults)
        let keep = jobs.currentJob
        let remove = jobs.addJob(name: "Alt", color: .gray, copyingRulesFrom: keep)
        jobs.select(remove)

        let context = container.mainContext
        context.insert(WorkSession(start: .now.addingTimeInterval(-7200), end: .now.addingTimeInterval(-3600), jobID: keep.uuid))
        context.insert(WorkSession(start: .now.addingTimeInterval(-3000), end: .now.addingTimeInterval(-1000), jobID: remove.uuid))
        tracker.start(job: remove)

        tracker.deleteJob(remove)

        #expect(jobs.jobs.map(\.uuid) == [keep.uuid])
        #expect(jobs.currentJob === keep)
        #expect(tracker.status == .idle)
        let remaining = try context.fetch(FetchDescriptor<WorkSession>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.jobID == keep.uuid)

        // The last job cannot be deleted.
        tracker.deleteJob(keep)
        #expect(jobs.jobs.count == 1)
    }
}

@MainActor
struct ThemeTests {
    private func makeSettings(_ name: String) -> (AppSettings, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (AppSettings(defaults: defaults), defaults)
    }

    @Test func catalogIsComplete() {
        let ids = AppTheme.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(AppTheme.all.allSatisfy { $0.light != nil || $0.dark != nil })
        #expect(AppTheme.named("dracula").fixedScheme == .dark)
        #expect(AppTheme.named("github").fixedScheme == nil)
        #expect(AppTheme.named("does-not-exist").id == AppTheme.standard.id)
    }

    @Test func themeAndAccentArePersistedAndApplied() {
        let (settings, defaults) = makeSettings("theme-tests")
        #expect(settings.themeID == AppTheme.standard.id)

        settings.themeID = "nord"
        settings.customAccentHex = "#F0883E"
        #expect(ThemeRuntime.theme.id == "nord")
        #expect(ThemeRuntime.customAccent?.hexString == "#F0883E")

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.themeID == "nord")
        #expect(reloaded.customAccentHex == "#F0883E")

        reloaded.customAccentHex = nil
        reloaded.themeID = AppTheme.standard.id
        #expect(ThemeRuntime.customAccent == nil)
        #expect(ThemeRuntime.theme.id == AppTheme.standard.id)
    }

    @Test func hexRoundTripAndContrast() {
        #expect(NSColor(hexString: "#0F9384")?.hexString == "#0F9384")
        #expect(NSColor(hexString: "zz") == nil)
        // Light accents get dark text on buttons, dark accents white text.
        #expect(NSColor(hex: 0x88C0D0).isLight)
        #expect(!NSColor(hex: 0x0F9384).isLight)
    }
}
