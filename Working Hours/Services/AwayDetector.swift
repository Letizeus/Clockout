import AppKit
import CoreGraphics

/// Notices when nobody used the Mac, or it slept, while the timer was running, and hands the
/// period to `TimeTracker.reportAway(_:)`. The user then decides whether it was a break.
@MainActor
final class AwayDetector {
    private let tracker: TimeTracker
    private let settings: AppSettings
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Start of the current idle stretch, once it is longer than the threshold.
    private var idleSince: Date?
    private var sleptAt: Date?

    private static let inputEvents: [CGEventType] = [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown, .flagsChanged,
    ]

    init(tracker: TimeTracker, settings: AppSettings) {
        self.tracker = tracker
        self.settings = settings

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdleTime() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.willSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didWake() }
            },
        ]
    }

    private var threshold: TimeInterval { TimeInterval(settings.awayDetectionMinutes * 60) }
    private var isActive: Bool { settings.awayDetectionMinutes > 0 && tracker.runningSession != nil }

    /// Seconds since the last keyboard or mouse input anywhere on the Mac.
    private var secondsSinceLastInput: TimeInterval {
        Self.inputEvents
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    private func checkIdleTime() {
        guard isActive else {
            idleSince = nil
            return
        }
        let idle = secondsSinceLastInput
        let now = Date.now
        if idle >= threshold {
            if idleSince == nil { idleSince = now.addingTimeInterval(-idle) }
        } else if let since = idleSince {
            idleSince = nil
            report(DateInterval(start: since, end: max(since, now.addingTimeInterval(-idle))))
        }
    }

    private func willSleep() {
        guard isActive else { return }
        sleptAt = idleSince ?? .now
    }

    private func didWake() {
        defer {
            sleptAt = nil
            idleSince = nil
        }
        guard let sleptAt, isActive else { return }
        report(DateInterval(start: sleptAt, end: max(sleptAt, .now)))
    }

    private func report(_ interval: DateInterval) {
        guard interval.duration >= threshold else { return }
        tracker.reportAway(interval)
        if settings.remindersEnabled {
            ReminderScheduler.notifyAway(minutes: Int(interval.duration / 60))
        }
    }
}
