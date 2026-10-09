import AppKit
import Foundation
import Observation

enum BreakFormat: String, CaseIterable, Identifiable {
    case clock
    case minutes
    case decimal

    var id: Self { self }

    var title: String {
        switch self {
        case .clock: String(localized: "Hours:minutes (00:30)")
        case .minutes: String(localized: "Minutes (30)")
        case .decimal: String(localized: "Decimal hours (0.50)")
        }
    }

    func strings(for duration: TimeInterval) -> (display: String, copy: String) {
        switch self {
        case .clock: (duration.paddedClock, duration.paddedClock)
        case .minutes: ("\(duration.wholeMinutes) min", "\(duration.wholeMinutes)")
        case .decimal: ("\(duration.decimalHours) h", duration.decimalHours)
        }
    }
}

enum TargetMode: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: Self { self }

    var title: String {
        switch self {
        case .daily: String(localized: "Per day")
        case .weekly: String(localized: "Per week")
        }
    }
}

/// App-wide preferences, persisted in `UserDefaults`. Working time rules live on each `Job`.
@Observable
final class AppSettings {
    enum Key {
        static let showsComplianceHints = "showsComplianceHints"
        static let showMenuBarExtra = "showMenuBarExtra"
        static let remindersEnabled = "remindersEnabled"
        static let breakReminderMinutes = "breakReminderMinutes"
        static let targetReminderEnabled = "targetReminderEnabled"
        static let breakStartedAt = "breakStartedAt"
        static let breakJobID = "breakJobID"
        static let currentJobID = "currentJobID"
        static let themeID = "themeID"
        static let appearanceMode = "appearanceMode"
        static let customAccent = "customAccent"
        static let holidayDetectionDone = "holidayDetectionDone"
        static let onboardingDone = "onboardingDone"
        static let awayDetectionMinutes = "awayDetectionMinutes"
    }

    /// Rules stored globally before jobs existed; read once to set up the first job.
    enum LegacyKey {
        static let dailyTargetMinutes = "dailyTargetMinutes"
        static let weeklyTargetMinutes = "weeklyTargetMinutes"
        static let targetMode = "targetMode"
        static let workdays = "workdays"
        static let roundingMinutes = "roundingMinutes"
        static let targetOnlyOnTrackedDays = "targetOnlyOnTrackedDays"
        static let breakFormat = "breakFormat"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var showsComplianceHints: Bool {
        didSet { defaults.set(showsComplianceHints, forKey: Key.showsComplianceHints) }
    }
    var showMenuBarExtra: Bool {
        didSet { defaults.set(showMenuBarExtra, forKey: Key.showMenuBarExtra) }
    }
    var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Key.remindersEnabled) }
    }
    /// 0 disables the break reminder.
    var breakReminderMinutes: Int {
        didSet { defaults.set(breakReminderMinutes, forKey: Key.breakReminderMinutes) }
    }
    var targetReminderEnabled: Bool {
        didSet { defaults.set(targetReminderEnabled, forKey: Key.targetReminderEnabled) }
    }
    /// The holiday region was looked up once at the first start, see `HolidaySetup`.
    var holidayDetectionDone: Bool {
        didSet { defaults.set(holidayDetectionDone, forKey: Key.holidayDetectionDone) }
    }
    var onboardingDone: Bool {
        didSet { defaults.set(onboardingDone, forKey: Key.onboardingDone) }
    }
    /// Idle time or sleep after which the app asks whether to take the time off as a break. 0 disables it.
    var awayDetectionMinutes: Int {
        didSet { defaults.set(awayDetectionMinutes, forKey: Key.awayDetectionMinutes) }
    }
    var themeID: String {
        didSet {
            defaults.set(themeID, forKey: Key.themeID)
            applyTheme()
        }
    }
    var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Key.appearanceMode) }
    }
    /// "#RRGGBB" or `nil` to use the theme's accent.
    var customAccentHex: String? {
        didSet {
            defaults.set(customAccentHex, forKey: Key.customAccent)
            applyTheme()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsComplianceHints = defaults.object(forKey: Key.showsComplianceHints) as? Bool ?? true
        showMenuBarExtra = defaults.object(forKey: Key.showMenuBarExtra) as? Bool ?? true
        remindersEnabled = defaults.object(forKey: Key.remindersEnabled) as? Bool ?? false
        breakReminderMinutes = defaults.object(forKey: Key.breakReminderMinutes) as? Int ?? 330
        targetReminderEnabled = defaults.object(forKey: Key.targetReminderEnabled) as? Bool ?? true
        holidayDetectionDone = defaults.bool(forKey: Key.holidayDetectionDone)
        onboardingDone = defaults.bool(forKey: Key.onboardingDone)
        awayDetectionMinutes = defaults.object(forKey: Key.awayDetectionMinutes) as? Int ?? 15
        themeID = defaults.string(forKey: Key.themeID) ?? AppTheme.standard.id
        appearanceMode = defaults.string(forKey: Key.appearanceMode).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        customAccentHex = defaults.string(forKey: Key.customAccent)
        applyTheme()
    }

    var theme: AppTheme { AppTheme.named(themeID) }

    /// Changes whenever colors have to be resolved again.
    var themeKey: String { "\(themeID)-\(customAccentHex ?? "")" }

    private func applyTheme() {
        ThemeRuntime.theme = AppTheme.named(themeID)
        ThemeRuntime.customAccent = customAccentHex.flatMap { NSColor(hexString: $0) }
    }
}
