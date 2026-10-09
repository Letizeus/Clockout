import SwiftUI

/// A titled card of rows with hairline separators, like a grouped form but in theme colors.
struct SettingsSection<Content: View>: View {
    var title: LocalizedStringResource?
    var footer: LocalizedStringResource?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows) { row in
                        row
                        if row.id != rows.last?.id {
                            Rectangle()
                                .fill(Color.hairline)
                                .frame(height: 1)
                                .padding(.leading, 14)
                        }
                    }
                }
            }
            .card(padding: 0)

            if let footer {
                Text(footer)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// Label on the left, control on the right.
struct SettingsRow<Control: View>: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.body)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 42)
    }
}

/// A row with a switch.
struct SettingsToggle: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle(isOn: $isOn) { Text(title) }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// Free-form content inside a section, padded like a row.
struct SettingsBlock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Text input that matches the cards.
struct ThemedTextField: View {
    let placeholder: LocalizedStringResource
    @Binding var text: String
    var width: CGFloat = 240

    var body: some View {
        TextField(text: $text, prompt: Text(placeholder)) { Text(placeholder) }
            .textFieldStyle(.plain)
            .font(AppFont.body)
            .padding(.horizontal, 8)
            .frame(width: width, height: 26)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.hairline)
            }
    }
}

/// A date in the style of `ThemedTextField`. Clicking it opens a calendar.
struct ThemedDateField: View {
    @Binding var date: Date
    /// Shows a clear button inside the field when set.
    var onClear: (() -> Void)?

    @State private var showsCalendar = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showsCalendar = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    // Explicit, because forms show the content of a labeled row in secondary color.
                    Text(date.numericDate)
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Choose date"))
            .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
                MonthCalendarView(
                    selection: Binding(
                        get: { date },
                        set: {
                            date = Calendar.app.startOfDay(for: $0)
                            showsCalendar = false
                        }
                    ),
                    showsSummary: false
                )
                .frame(width: 260)
                .padding(12)
                .background(Color.surface)
                .presentationBackground(Color.surface)
            }

            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(Text("Remove date"))
            }
        }
        .font(AppFont.body)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.surfaceRaised.opacity(isHovered ? 1 : 0.8), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.hairline)
        }
        .fixedSize()
        .onHover { isHovered = $0 }
    }
}

/// Weekday chips, filled when selected.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    /// Monday first, with short names in the app's language ("Mo", "Mon").
    private let weekdays: [(number: Int, symbol: String)] = [2, 3, 4, 5, 6, 7, 1].map { number in
        let symbol = Calendar.app.shortStandaloneWeekdaySymbols[number - 1].replacingOccurrences(of: ".", with: "")
        return (number, String(symbol.prefix(3)))
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(weekdays, id: \.number) { weekday in
                let isOn = selection.contains(weekday.number)
                Button {
                    if isOn {
                        selection.remove(weekday.number)
                    } else {
                        selection.insert(weekday.number)
                    }
                } label: {
                    Text(weekday.symbol)
                        .font(AppFont.label)
                        .foregroundStyle(isOn ? Color.onBrand : Color.secondary)
                        .frame(width: 32, height: 24)
                        .background(
                            isOn ? Color.brand : Color.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekday.symbol)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Inline warning shown inside a section.
struct SettingsNotice: View {
    let systemImage: String
    var tint: Color = .amber
    let text: LocalizedStringResource

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .font(AppFont.body)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
