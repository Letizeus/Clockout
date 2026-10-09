import SwiftUI

/// Month grid that fills its column and marks days with tracked time.
struct MonthCalendarView: View {
    @Binding var selection: Date
    /// Worked time keyed by start of day.
    let workedByDay: [Date: TimeInterval]
    /// Vacation, sick days and holidays keyed by start of day.
    var absenceByDay: [Date: AbsenceKind] = [:]
    /// The line with the month total below the grid.
    var showsSummary = true
    /// Name of the public holiday on a day, if any.
    var holidayTitle: (Date) -> String? = { _ in nil }

    @State private var displayedMonth: Date

    private let calendar = Calendar.app
    private let weekdaySymbols = [2, 3, 4, 5, 6, 7, 1].map {
        String(Calendar.app.shortStandaloneWeekdaySymbols[$0 - 1].replacingOccurrences(of: ".", with: "").prefix(3))
    }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    init(
        selection: Binding<Date>,
        workedByDay: [Date: TimeInterval] = [:],
        absenceByDay: [Date: AbsenceKind] = [:],
        holidayTitle: @escaping (Date) -> String? = { _ in nil },
        showsSummary: Bool = true
    ) {
        _selection = selection
        self.workedByDay = workedByDay
        self.absenceByDay = absenceByDay
        self.holidayTitle = holidayTitle
        self.showsSummary = showsSummary
        _displayedMonth = State(initialValue: Calendar.app.dateInterval(of: .month, for: selection.wrappedValue)?.start ?? selection.wrappedValue)
    }

    /// Always six rows so the height does not jump between months.
    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let leading = (calendar.component(.weekday, from: displayedMonth) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: displayedMonth))
        }
        return cells + Array(repeating: nil, count: max(0, 42 - cells.count))
    }

    private var monthTotal: (worked: TimeInterval, days: Int, absent: Int) {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return (0, 0, 0) }
        let entries = workedByDay.filter { interval.contains($0.key) && $0.value > 0 }
        let absent = absenceByDay.keys.filter { interval.contains($0) }.count
        return (entries.values.reduce(0, +), entries.count, absent)
    }

    private func totalText(_ total: (worked: TimeInterval, days: Int, absent: Int)) -> String {
        var parts: [String] = []
        if total.days > 0 {
            let days = String(localized: "on \(total.days) days")
            parts.append(String(localized: "\(total.worked.clock) h \(days)"))
        }
        if total.absent > 0 {
            parts.append(String(localized: "\(total.absent) days absent"))
        }
        return parts.isEmpty ? String(localized: "No entries this month") : parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 2) {
                Text(displayedMonth.monthTitle)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    showMonth(offset: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .help("Previous Month")
                Button("Today") {
                    selection = calendar.startOfDay(for: .now)
                }
                .help("Jump to today")
                Button {
                    showMonth(offset: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .help("Next Month")
            }
            .buttonStyle(.ghost)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(AppFont.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DayCell(
                            date: date,
                            worked: workedByDay[date] ?? 0,
                            absence: absenceByDay[date],
                            holiday: holidayTitle(date),
                            isSelected: calendar.isDate(date, inSameDayAs: selection),
                            isToday: calendar.isDateInToday(date),
                            isWeekend: calendar.isDateInWeekend(date)
                        ) {
                            selection = date
                        }
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }

            if showsSummary {
                Text(totalText(monthTotal))
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: selection) {
            if let month = calendar.dateInterval(of: .month, for: selection)?.start, month != displayedMonth {
                displayedMonth = month
            }
        }
    }

    private func showMonth(offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
    }
}

private struct DayCell: View {
    let date: Date
    let worked: TimeInterval
    let absence: AbsenceKind?
    let holiday: String?
    let isSelected: Bool
    let isToday: Bool
    let isWeekend: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(Calendar.app.component(.day, from: date))")
                    .font(.system(size: 12.5, weight: isToday || isSelected ? .semibold : .regular).monospacedDigit())
                HStack(spacing: 3) {
                    if worked > 0 {
                        Circle()
                            .fill(isSelected ? Color.canvas.opacity(0.8) : Color.brand.opacity(0.8))
                            .frame(width: 4, height: 4)
                    }
                    if absence != nil || holiday != nil {
                        Circle()
                            .fill(Color.amber)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .foregroundStyle(foreground)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.primary : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
    }

    private var helpText: String {
        var parts: [String] = []
        if let absence { parts.append(absence.title) }
        if let holiday { parts.append(holiday) }
        if worked > 0 { parts.append(String(localized: "\(worked.clock) h worked")) }
        return parts.joined(separator: ", ")
    }

    private var foreground: Color {
        if isSelected { return .canvas }
        if isToday { return .brand }
        return isWeekend ? .secondary : .primary
    }
}
