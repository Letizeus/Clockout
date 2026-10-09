import SwiftUI

/// Hours and minutes input with a stepper. Typing accepts "38:30", "38,5" or "38".
struct DurationField: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let step: Int

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Duration", text: $text)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 60)
                .focused($isFocused)
                .onSubmit(commit)
            Text("h")
                .foregroundStyle(.secondary)
            Stepper("Duration", value: $minutes, in: range, step: step)
                .labelsHidden()
        }
        .onAppear { text = Self.format(minutes) }
        .onChange(of: minutes) { text = Self.format(minutes) }
        .onChange(of: isFocused) {
            if !isFocused { commit() }
        }
    }

    private func commit() {
        if let value = Self.parse(text) {
            minutes = min(max(value, range.lowerBound), range.upperBound)
        }
        text = Self.format(minutes)
    }

    static func format(_ minutes: Int) -> String {
        TimeInterval(minutes * 60).clock
    }

    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "h", with: "")
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let hours = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let minutes = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                  hours >= 0, (0..<60).contains(minutes)
            else { return nil }
            return hours * 60 + minutes
        }
        guard let hours = Double(trimmed.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)),
              hours >= 0
        else { return nil }
        return Int((hours * 60).rounded())
    }
}
