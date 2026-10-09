import SwiftUI

/// A time in the style of `ThemedDateField`. Typing accepts "8:30", "08.30", "830" or "8";
/// the arrow keys move it by five minutes.
struct ThemedTimeField: View {
    @Binding var date: Date

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Time", text: $text)
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(AppFont.body.monospacedDigit())
            .multilineTextAlignment(.center)
            .focused($isFocused)
            .onSubmit(commit)
            .onKeyPress(.upArrow) { step(by: 5) }
            .onKeyPress(.downArrow) { step(by: -5) }
            .frame(width: 52, height: 26)
            .background(Color.surfaceRaised.opacity(isFocused ? 1 : 0.8), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isFocused ? Color.brand.opacity(0.7) : Color.hairline)
            }
            .onAppear { text = date.clockTime }
            .onChange(of: date) { if !isFocused { text = date.clockTime } }
            .onChange(of: isFocused) { if !isFocused { commit() } }
    }

    private func commit() {
        guard let minutes = TimesheetImporter.parseTime(.text(text)) else {
            text = date.clockTime
            return
        }
        let day = Calendar.app.startOfDay(for: date)
        date = Calendar.app.date(byAdding: .minute, value: minutes, to: day) ?? date
        text = date.clockTime
    }

    private func step(by minutes: Int) -> KeyPress.Result {
        commit()
        date = Calendar.app.date(byAdding: .minute, value: minutes, to: date) ?? date
        text = date.clockTime
        return .handled
    }
}

/// Day and time of one moment, e.g. the start of a work block.
struct ThemedDateTimeField: View {
    @Binding var date: Date

    var body: some View {
        HStack(spacing: 6) {
            ThemedDateField(date: Binding(
                get: { date },
                set: { day in
                    // Keep the time when another day is picked.
                    let calendar = Calendar.app
                    let time = calendar.dateComponents([.hour, .minute], from: date)
                    date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
                }
            ))
            ThemedTimeField(date: $date)
        }
    }
}
