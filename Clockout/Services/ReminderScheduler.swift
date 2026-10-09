import Foundation
import UserNotifications

/// Local notifications while a work block is running.
enum ReminderScheduler {
    private static let breakIdentifier = "reminder.break"
    private static let targetIdentifier = "reminder.target"
    private static let awayIdentifier = "reminder.away"

    /// The notification settings of this app in System Settings.
    static var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")!
    }

    /// False when notifications were turned off for this app in System Settings.
    static func isAllowedBySystem() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus != .denied
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func scheduleForWorkBlock(starting start: Date, workedBefore: TimeInterval, job: Job, settings: AppSettings) {
        cancelWorkBlockReminders()
        guard settings.remindersEnabled else { return }

        if settings.breakReminderMinutes > 0 {
            let after = TimeInterval(settings.breakReminderMinutes * 60)
            schedule(
                identifier: breakIdentifier,
                title: String(localized: "Time for a break"),
                body: String(localized: "You have been working for \(after.clock) hours straight. After 6 hours of work, a 30-minute break is required."),
                at: start.addingTimeInterval(after)
            )
        }

        let target = job.rules.plannedTarget(for: start)
        if settings.targetReminderEnabled, target > 0 {
            let remaining = target - workedBefore
            if remaining > 0 {
                schedule(
                    identifier: targetIdentifier,
                    title: String(localized: "Target reached"),
                    body: String(localized: "You worked \(target.clock) hours for \(job.displayName) today."),
                    at: start.addingTimeInterval(remaining)
                )
            }
        }
    }

    /// Right away, so the decision is not missed while the window is closed.
    static func notifyAway(minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "You were away for \(minutes) minutes")
        content.body = String(localized: "The timer kept running. Open Clockout to take the time off as a break.")
        content.sound = .default
        let request = UNNotificationRequest(identifier: awayIdentifier, content: content, trigger: nil)
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelWorkBlockReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [breakIdentifier, targetIdentifier])
    }

    private static func schedule(identifier: String, title: String, body: String, at date: Date) {
        let delay = date.timeIntervalSinceNow
        guard delay > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
