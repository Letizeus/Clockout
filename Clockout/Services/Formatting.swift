import Foundation

extension Locale {
    /// The app's language (English or German, following the system) with the user's region
    /// for the details of numbers and dates.
    static let app: Locale = {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: language)
        return Locale(components: components)
    }()
}

extension Calendar {
    /// Weeks start on Monday and are numbered by ISO 8601, as on most timesheets.
    static let app: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .app
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()
}

enum AppFormatters {
    static let clockTime = dateFormatter("HH:mm")
    static let numericDate = dateFormatter(template: "ddMMyyyy")

    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .app
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static func dateFormatter(_ format: String? = nil, template: String? = nil) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .app
        formatter.calendar = .app
        formatter.timeZone = Calendar.app.timeZone
        if let format { formatter.dateFormat = format }
        if let template { formatter.setLocalizedDateFormatFromTemplate(template) }
        return formatter
    }
}

extension Date {
    /// "08:05"
    var clockTime: String { AppFormatters.clockTime.string(from: self) }
    /// "08.10.2026" or "10/08/2026", depending on the locale.
    var numericDate: String { AppFormatters.numericDate.string(from: self) }
    /// "Thursday, October 8, 2026"
    var dayTitle: String { formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(.app)) }
    /// "Thu, Oct 8"
    var shortDayTitle: String { formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(.app)) }
    /// "Thursday"
    var weekdayName: String { formatted(.dateTime.weekday(.wide).locale(.app)) }
    /// "October 2026"
    var monthTitle: String { formatted(.dateTime.month(.wide).year().locale(.app)) }
}

extension TimeInterval {
    var wholeMinutes: Int { Int((self / 60).rounded()) }

    /// "7:05", "-0:30"
    var clock: String {
        let minutes = wholeMinutes
        let sign = minutes < 0 ? "-" : ""
        return sign + "\(abs(minutes) / 60):" + String(format: "%02d", abs(minutes) % 60)
    }

    /// "07:05", the format most timesheets expect.
    var paddedClock: String {
        let minutes = abs(wholeMinutes)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// "+0:15", "-1:30", "0:00"
    var signedClock: String {
        wholeMinutes > 0 ? "+" + clock : clock
    }

    /// "7:05:42"
    var stopwatch: String {
        let seconds = Swift.max(0, Int(self))
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    /// "7.75" or "7,75", depending on the locale.
    var decimalHours: String {
        AppFormatters.decimal.string(from: NSNumber(value: self / 3600)) ?? ""
    }
}
