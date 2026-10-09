import AppKit
import Foundation
import Observation
import OSLog

/// Looks up the latest GitHub release at most once a day and offers it when it is newer.
/// The request carries no data about the user; the download happens in the browser.
@Observable
final class UpdateChecker {
    /// Owner and name of the GitHub repository that publishes the releases.
    static let repository = "Letizeus/clockout"
    private static let checkInterval: TimeInterval = 24 * 3600
    /// A release description is a few KB; anything much larger is not what we asked for.
    private static let maximumResponseSize = 512 * 1024

    struct Release: Equatable {
        let version: String
        let pageURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed
    }

    enum Key {
        static let isEnabled = "checksForUpdates"
        static let lastCheck = "lastUpdateCheck"
        static let skippedVersion = "skippedUpdateVersion"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let logger = Logger(subsystem: "Clockout", category: "UpdateChecker")
    @ObservationIgnored private var timer: Timer?

    private(set) var state: State = .idle

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    /// The newer release, unless the user chose to skip it.
    var offeredRelease: Release? {
        guard case .available(let release) = state, release.version != defaults.string(forKey: Key.skippedVersion) else { return nil }
        return release
    }

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    ) {
        self.defaults = defaults
        self.session = session
        self.currentVersion = currentVersion
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
    }

    /// Checks now if the last check is older than a day, and keeps doing so while the app runs.
    func start() {
        Task { await checkIfDue() }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.checkIfDue() }
            }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func checkIfDue() async {
        guard isEnabled else { return }
        let last = defaults.object(forKey: Key.lastCheck) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) >= Self.checkInterval else { return }
        await check()
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            defaults.set(Date.now, forKey: Key.lastCheck)
            state = release.map { Self.isVersion($0.version, newerThan: currentVersion) ? .available($0) : .upToDate } ?? .upToDate
        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
            state = .failed
        }
    }

    func skip(_ release: Release) {
        defaults.set(release.version, forKey: Key.skippedVersion)
        state = .upToDate
    }

    func openDownloadPage(for release: Release) {
        NSWorkspace.shared.open(release.pageURL)
    }

    // MARK: Parsing

    private func fetchLatestRelease() async throws -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        // No release published yet.
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200, data.count <= Self.maximumResponseSize else { throw URLError(.badServerResponse) }
        return Self.release(from: data)
    }

    /// Reads tag and page from GitHub's release JSON. Pages outside the repository are ignored,
    /// so a manipulated response cannot send the user somewhere else.
    static func release(from data: Data) -> Release? {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let url = URL(string: payload.html_url),
              url.scheme == "https", url.host == "github.com",
              url.path.lowercased().hasPrefix("/\(repository.lowercased())/releases")
        else { return nil }
        let version = payload.tag_name.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard !version.isEmpty, version.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Release(version: version, pageURL: url)
    }

    /// Compares dotted version numbers: "1.10" is newer than "1.9", "1.1" equals "1.1.0".
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
