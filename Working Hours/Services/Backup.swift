import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Everything the app stores about jobs and entries, as one JSON file. Preferences such as the
/// theme stay out, so a backup can also move data to a friend's Mac without changing their look.
struct Backup: Codable {
    static let format = "working-hours-backup"
    static let currentVersion = 1
    /// Backups are a few MB at most; larger files are refused before decoding.
    static let maximumFileSize = 100 * 1024 * 1024

    struct JobData: Codable {
        var uuid: UUID
        var name: String
        var colorName: String
        var sortIndex: Int
        var createdAt: Date
        var targetModeRaw: String
        var dailyTargetMinutes: Int
        var weeklyTargetMinutes: Int
        var workdayList: [Int]
        var roundingMinutes: Int
        var targetOnlyOnTrackedDays: Bool
        var breakFormatRaw: String
        var iconData: Data?
        var balanceCarryOverMinutes: Int
        var balanceCarryOverDate: Date?
        var startDate: Date?
        var absences: [Absence]
        var holidaysEnabled: Bool
        var holidayRegionCode: String
        var ignoredHolidayList: [String]
    }

    struct SessionData: Codable {
        var start: Date
        var end: Date?
        var note: String
        var jobID: UUID?
    }

    var format = Backup.format
    var version = Backup.currentVersion
    var createdAt: Date
    var currentJobID: UUID?
    var jobs: [JobData]
    var sessions: [SessionData]

    var firstEntry: Date? { sessions.map(\.start).min() }

    // MARK: Creating

    init(jobs: [Job], sessions: [WorkSession], currentJobID: UUID?, createdAt: Date = .now) {
        self.createdAt = createdAt
        self.currentJobID = currentJobID
        self.jobs = jobs.map { job in
            JobData(
                uuid: job.uuid,
                name: job.name,
                colorName: job.colorName,
                sortIndex: job.sortIndex,
                createdAt: job.createdAt,
                targetModeRaw: job.targetModeRaw,
                dailyTargetMinutes: job.dailyTargetMinutes,
                weeklyTargetMinutes: job.weeklyTargetMinutes,
                workdayList: job.workdayList,
                roundingMinutes: job.roundingMinutes,
                targetOnlyOnTrackedDays: job.targetOnlyOnTrackedDays,
                breakFormatRaw: job.breakFormatRaw,
                iconData: job.iconData,
                balanceCarryOverMinutes: job.balanceCarryOverMinutes,
                balanceCarryOverDate: job.balanceCarryOverDate,
                startDate: job.startDate,
                absences: job.absences,
                holidaysEnabled: job.holidaysEnabled,
                holidayRegionCode: job.holidayRegionCode,
                ignoredHolidayList: job.ignoredHolidayList
            )
        }
        self.sessions = sessions.map { SessionData(start: $0.start, end: $0.end, note: $0.note, jobID: $0.jobID) }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: Reading

    enum ReadError: LocalizedError {
        case tooLarge
        case notABackup
        case newerVersion

        var errorDescription: String? {
            switch self {
            case .tooLarge: String(localized: "The file is too large for a backup.")
            case .notABackup: String(localized: "The file is not a Working Hours backup.")
            case .newerVersion: String(localized: "This backup is from a newer version. Update Working Hours first.")
            }
        }
    }

    static func read(from url: URL) throws -> Backup {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumFileSize {
            throw ReadError.tooLarge
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> Backup {
        guard data.count <= maximumFileSize else { throw ReadError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(Backup.self, from: data), backup.format == format, !backup.jobs.isEmpty else {
            throw ReadError.notABackup
        }
        guard backup.version <= currentVersion else { throw ReadError.newerVersion }
        return backup
    }

    // MARK: Restoring

    /// Replaces all jobs and entries with the backup's.
    @MainActor
    func restore(into context: ModelContext, tracker: TimeTracker, jobStore: JobStore) throws {
        tracker.stop()
        for session in try context.fetch(FetchDescriptor<WorkSession>()) {
            context.delete(session)
        }
        for job in try context.fetch(FetchDescriptor<Job>()) {
            context.delete(job)
        }

        var restoredIDs = Set<UUID>()
        let restoredJobs = jobs.map { data in
            let job = Job(name: data.name, sortIndex: data.sortIndex)
            job.uuid = data.uuid
            job.colorName = data.colorName
            job.createdAt = data.createdAt
            job.targetModeRaw = data.targetModeRaw
            job.dailyTargetMinutes = min(max(data.dailyTargetMinutes, 0), 24 * 60)
            job.weeklyTargetMinutes = min(max(data.weeklyTargetMinutes, 0), 7 * 24 * 60)
            job.workdayList = data.workdayList.filter { (1...7).contains($0) }
            job.roundingMinutes = [1, 5, 10, 15, 30].contains(data.roundingMinutes) ? data.roundingMinutes : 1
            job.targetOnlyOnTrackedDays = data.targetOnlyOnTrackedDays
            job.breakFormatRaw = data.breakFormatRaw
            // Pictures are re-encoded, so a crafted file cannot hand arbitrary image data to the decoders later.
            job.iconData = data.iconData.flatMap(JobIconImage.makeIconData(from:))
            job.balanceCarryOverMinutes = data.balanceCarryOverMinutes
            job.balanceCarryOverDate = data.balanceCarryOverDate
            job.startDate = data.startDate
            job.absences = data.absences
            job.holidaysEnabled = data.holidaysEnabled
            job.holidayRegionCode = data.holidayRegionCode
            job.ignoredHolidayList = data.ignoredHolidayList
            context.insert(job)
            restoredIDs.insert(job.uuid)
            return job
        }

        for data in sessions where data.end.map({ $0 >= data.start }) ?? true {
            // Entries of a job that is not in the backup go to the first job instead of disappearing.
            let jobID = data.jobID.flatMap { restoredIDs.contains($0) ? $0 : nil } ?? restoredJobs.first?.uuid
            context.insert(WorkSession(start: data.start, end: data.end, note: data.note, jobID: jobID))
        }

        jobStore.replaceAll(with: restoredJobs, selecting: currentJobID)
        tracker.sessionsDidChange()
        tracker.rescheduleReminders()
    }
}

/// The JSON file for `fileExporter`.
nonisolated struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
