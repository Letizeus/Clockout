import Foundation

enum HolidayCountry: String, CaseIterable, Identifiable, Codable {
    case germany = "DE"
    case austria = "AT"
    case switzerland = "CH"

    var id: Self { self }

    var title: String {
        switch self {
        case .germany: String(localized: "Germany")
        case .austria: String(localized: "Austria")
        case .switzerland: String(localized: "Switzerland")
        }
    }
}

enum GermanState: String, CaseIterable, Identifiable, Codable {
    case badenWuerttemberg = "BW"
    case bavaria = "BY"
    case berlin = "BE"
    case brandenburg = "BB"
    case bremen = "HB"
    case hamburg = "HH"
    case hesse = "HE"
    case mecklenburgVorpommern = "MV"
    case lowerSaxony = "NI"
    case northRhineWestphalia = "NW"
    case rhinelandPalatinate = "RP"
    case saarland = "SL"
    case saxony = "SN"
    case saxonyAnhalt = "ST"
    case schleswigHolstein = "SH"
    case thuringia = "TH"

    var id: Self { self }

    var title: String {
        switch self {
        case .badenWuerttemberg: String(localized: "Baden-Württemberg")
        case .bavaria: String(localized: "Bavaria")
        case .berlin: String(localized: "Berlin")
        case .brandenburg: String(localized: "Brandenburg")
        case .bremen: String(localized: "Bremen")
        case .hamburg: String(localized: "Hamburg")
        case .hesse: String(localized: "Hesse")
        case .mecklenburgVorpommern: String(localized: "Mecklenburg-Western Pomerania")
        case .lowerSaxony: String(localized: "Lower Saxony")
        case .northRhineWestphalia: String(localized: "North Rhine-Westphalia")
        case .rhinelandPalatinate: String(localized: "Rhineland-Palatinate")
        case .saarland: String(localized: "Saarland")
        case .saxony: String(localized: "Saxony")
        case .saxonyAnhalt: String(localized: "Saxony-Anhalt")
        case .schleswigHolstein: String(localized: "Schleswig-Holstein")
        case .thuringia: String(localized: "Thuringia")
        }
    }

    /// German and English names as returned by the geocoder, folded for comparison.
    private var names: [String] {
        switch self {
        case .badenWuerttemberg: ["Baden-Württemberg"]
        case .bavaria: ["Bayern", "Bavaria"]
        case .berlin: ["Berlin"]
        case .brandenburg: ["Brandenburg"]
        case .bremen: ["Bremen", "Freie Hansestadt Bremen"]
        case .hamburg: ["Hamburg", "Freie und Hansestadt Hamburg"]
        case .hesse: ["Hessen", "Hesse"]
        case .mecklenburgVorpommern: ["Mecklenburg-Vorpommern", "Mecklenburg-Western Pomerania"]
        case .lowerSaxony: ["Niedersachsen", "Lower Saxony"]
        case .northRhineWestphalia: ["Nordrhein-Westfalen", "North Rhine-Westphalia"]
        case .rhinelandPalatinate: ["Rheinland-Pfalz", "Rhineland-Palatinate"]
        case .saarland: ["Saarland"]
        case .saxony: ["Sachsen", "Saxony"]
        case .saxonyAnhalt: ["Sachsen-Anhalt", "Saxony-Anhalt"]
        case .schleswigHolstein: ["Schleswig-Holstein"]
        case .thuringia: ["Thüringen", "Thuringia"]
        }
    }

    /// Matches "Bayern", "Bavaria" or "BY".
    init?(name: String) {
        let folded = Self.fold(name)
        guard let state = Self.allCases.first(where: { state in
            Self.fold(state.rawValue) == folded || state.names.contains { Self.fold($0) == folded }
        }) else { return nil }
        self = state
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter }
    }
}

/// Where the public holidays come from: a country, and for Germany optionally a state.
/// Without a state only the nationwide German holidays apply.
struct HolidayRegion: Hashable, Codable {
    var country: HolidayCountry
    var state: GermanState?

    init(country: HolidayCountry, state: GermanState? = nil) {
        self.country = country
        self.state = country == .germany ? state : nil
    }

    /// "DE-BY", "DE", "AT".
    init?(code: String) {
        let parts = code.split(separator: "-").map(String.init)
        guard let first = parts.first, let country = HolidayCountry(rawValue: first) else { return nil }
        self.init(country: country, state: parts.count > 1 ? GermanState(rawValue: parts[1]) : nil)
    }

    var code: String {
        state.map { "\(country.rawValue)-\($0.rawValue)" } ?? country.rawValue
    }

    var title: String {
        guard let state else { return country == .germany ? String(localized: "Germany (nationwide only)") : country.title }
        return "\(state.title), \(country.title)"
    }
}

enum HolidayKind: String, CaseIterable, Codable {
    case newYear
    case berchtoldsDay
    case epiphany
    case womensDay
    case goodFriday
    case easterSunday
    case easterMonday
    case labourDay
    case ascension
    case whitSunday
    case whitMonday
    case corpusChristi
    case swissNationalDay
    case assumption
    case childrensDay
    case germanUnity
    case austrianNationalDay
    case reformationDay
    case allSaints
    case repentanceDay
    case immaculateConception
    case christmasDay
    case stStephensDay

    func title(in country: HolidayCountry) -> String {
        switch self {
        case .newYear: String(localized: "New Year's Day")
        case .berchtoldsDay: String(localized: "Berchtold's Day")
        case .epiphany: String(localized: "Epiphany")
        case .womensDay: String(localized: "International Women's Day")
        case .goodFriday: String(localized: "Good Friday")
        case .easterSunday: String(localized: "Easter Sunday")
        case .easterMonday: String(localized: "Easter Monday")
        case .labourDay: country == .austria ? String(localized: "State Holiday") : String(localized: "Labour Day")
        case .ascension: country == .switzerland ? String(localized: "holiday.ascension.ch", defaultValue: "Ascension Day") : String(localized: "Ascension Day")
        case .whitSunday: String(localized: "Whit Sunday")
        case .whitMonday: String(localized: "Whit Monday")
        case .corpusChristi: String(localized: "Corpus Christi")
        case .swissNationalDay: String(localized: "Swiss National Day")
        case .assumption: String(localized: "Assumption Day")
        case .childrensDay: String(localized: "World Children's Day")
        case .germanUnity: String(localized: "German Unity Day")
        case .austrianNationalDay: String(localized: "Austrian National Day")
        case .reformationDay: String(localized: "Reformation Day")
        case .allSaints: String(localized: "All Saints' Day")
        case .repentanceDay: String(localized: "Day of Repentance and Prayer")
        case .immaculateConception: String(localized: "Immaculate Conception")
        case .christmasDay:
            switch country {
            case .germany: String(localized: "Christmas Day")
            case .austria: String(localized: "holiday.christmas.at", defaultValue: "Christmas Day")
            case .switzerland: String(localized: "holiday.christmas.ch", defaultValue: "Christmas Day")
            }
        case .stStephensDay:
            switch country {
            case .germany: String(localized: "Boxing Day")
            case .austria: String(localized: "holiday.stephen.at", defaultValue: "St. Stephen's Day")
            case .switzerland: String(localized: "St. Stephen's Day")
            }
        }
    }

    /// Holidays of a region. Switzerland lists the days most cantons share.
    static func kinds(for region: HolidayRegion) -> [HolidayKind] {
        switch region.country {
        case .austria:
            return [
                .newYear, .epiphany, .easterMonday, .labourDay, .ascension, .whitMonday, .corpusChristi,
                .assumption, .austrianNationalDay, .allSaints, .immaculateConception, .christmasDay, .stStephensDay,
            ]
        case .switzerland:
            return [
                .newYear, .berchtoldsDay, .goodFriday, .easterMonday, .ascension, .whitMonday,
                .swissNationalDay, .christmasDay, .stStephensDay,
            ]
        case .germany:
            var kinds: [HolidayKind] = [
                .newYear, .goodFriday, .easterMonday, .labourDay, .ascension, .whitMonday,
                .germanUnity, .christmasDay, .stStephensDay,
            ]
            guard let state = region.state else { return kinds }
            let extras: [(HolidayKind, Set<GermanState>)] = [
                (.epiphany, [.badenWuerttemberg, .bavaria, .saxonyAnhalt]),
                (.womensDay, [.berlin, .mecklenburgVorpommern]),
                (.easterSunday, [.brandenburg]),
                (.whitSunday, [.brandenburg]),
                (.corpusChristi, [.badenWuerttemberg, .bavaria, .hesse, .northRhineWestphalia, .rhinelandPalatinate, .saarland]),
                // In Bavaria only in mostly Catholic municipalities, which is most of them. It can be switched off.
                (.assumption, [.saarland, .bavaria]),
                (.childrensDay, [.thuringia]),
                (.reformationDay, [
                    .brandenburg, .bremen, .hamburg, .mecklenburgVorpommern, .lowerSaxony,
                    .saxony, .saxonyAnhalt, .schleswigHolstein, .thuringia,
                ]),
                (.allSaints, [.badenWuerttemberg, .bavaria, .northRhineWestphalia, .rhinelandPalatinate, .saarland]),
                (.repentanceDay, [.saxony]),
            ]
            kinds += extras.filter { $0.1.contains(state) }.map(\.0)
            return kinds
        }
    }

    func date(in year: Int, calendar: Calendar) -> Date? {
        func fixed(_ month: Int, _ day: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
        func easter(plus days: Int) -> Date? {
            HolidayCalendar.easterSunday(year: year, calendar: calendar)
                .flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
        }

        switch self {
        case .newYear: return fixed(1, 1)
        case .berchtoldsDay: return fixed(1, 2)
        case .epiphany: return fixed(1, 6)
        case .womensDay: return fixed(3, 8)
        case .goodFriday: return easter(plus: -2)
        case .easterSunday: return easter(plus: 0)
        case .easterMonday: return easter(plus: 1)
        case .labourDay: return fixed(5, 1)
        case .ascension: return easter(plus: 39)
        case .whitSunday: return easter(plus: 49)
        case .whitMonday: return easter(plus: 50)
        case .corpusChristi: return easter(plus: 60)
        case .swissNationalDay: return fixed(8, 1)
        case .assumption: return fixed(8, 15)
        case .childrensDay: return fixed(9, 20)
        case .germanUnity: return fixed(10, 3)
        case .austrianNationalDay: return fixed(10, 26)
        case .reformationDay: return fixed(10, 31)
        case .allSaints: return fixed(11, 1)
        case .repentanceDay:
            // The Wednesday before 23 November.
            guard let november22 = fixed(11, 22) else { return nil }
            let weekday = calendar.component(.weekday, from: november22)
            return calendar.date(byAdding: .day, value: -((weekday - 4 + 7) % 7), to: november22)
        case .immaculateConception: return fixed(12, 8)
        case .christmasDay: return fixed(12, 25)
        case .stStephensDay: return fixed(12, 26)
        }
    }
}

struct Holiday: Hashable {
    let kind: HolidayKind
    /// Start of the day.
    let date: Date
    let title: String
}

enum HolidayCalendar {
    private struct Key: Hashable {
        let region: HolidayRegion
        let year: Int
    }

    /// The statistics ask for every day of a year, so each year is computed once.
    private static var cache: [Key: [Date: Holiday]] = [:]

    static func holidays(in year: Int, region: HolidayRegion, calendar: Calendar = .app) -> [Date: Holiday] {
        let key = Key(region: region, year: year)
        if let cached = cache[key] { return cached }

        var result: [Date: Holiday] = [:]
        for kind in HolidayKind.kinds(for: region) {
            guard let date = kind.date(in: year, calendar: calendar) else { continue }
            let day = calendar.startOfDay(for: date)
            result[day] = Holiday(kind: kind, date: day, title: kind.title(in: region.country))
        }
        cache[key] = result
        return result
    }

    static func holiday(on day: Date, region: HolidayRegion, calendar: Calendar = .app) -> Holiday? {
        let start = calendar.startOfDay(for: day)
        return holidays(in: calendar.component(.year, from: start), region: region, calendar: calendar)[start]
    }

    /// Gregorian Easter Sunday (anonymous Gregorian algorithm).
    static func easterSunday(year: Int, calendar: Calendar = .app) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
