import SwiftUI

/// Form rows to set a job's opening balance. Used in the settings and from the total balance in the stats.
struct CarryOverFields: View {
    @Bindable var job: Job

    var body: some View {
        SettingsToggle(title: "Use carry-over", isOn: Binding(
            get: { job.balanceCarryOverDate != nil },
            set: { isOn in
                if isOn {
                    let calendar = Calendar.app
                    job.balanceCarryOverDate = calendar.dateInterval(of: .year, for: .now)?.start ?? calendar.startOfDay(for: .now)
                } else {
                    job.balanceCarryOverDate = nil
                    job.balanceCarryOverMinutes = 0
                }
            }
        ))

        if job.balanceCarryOverDate != nil {
            SettingsRow(title: "Carry-over") {
                SignedDurationField(minutes: $job.balanceCarryOverMinutes)
            }
            SettingsRow(title: "As of") {
                ThemedDateField(date: Binding(
                    get: { job.balanceCarryOverDate ?? .now },
                    set: { job.balanceCarryOverDate = $0 }
                ))
            }
        }
    }
}

/// Plus or minus, then hours and minutes.
struct SignedDurationField: View {
    @Binding var minutes: Int

    @State private var isNegative = false

    var body: some View {
        HStack(spacing: 8) {
            PillTabs(
                options: [(false, String(localized: "Plus")), (true, String(localized: "Minus"))],
                selection: Binding(
                    get: { minutes < 0 || (minutes == 0 && isNegative) },
                    set: { negative in
                        isNegative = negative
                        minutes = (negative ? -1 : 1) * abs(minutes)
                    }
                )
            )

            DurationField(
                minutes: Binding(
                    get: { abs(minutes) },
                    set: { minutes = (minutes < 0 || isNegative ? -1 : 1) * $0 }
                ),
                range: 0...(999 * 60),
                step: 30
            )
        }
        .onAppear { isNegative = minutes < 0 }
    }
}

/// Where the carry-over is explained in both places.
enum CarryOverText {
    static let footer: LocalizedStringResource = "Starting balance as of this date; earlier work blocks stay but no longer count."
}
