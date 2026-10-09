import SwiftUI

/// First start without any entries: name, working time and holidays of the first job.
struct OnboardingView: View {
    @Bindable var job: Job

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(JobStore.self) private var jobs

    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("e.g. student job, part-time job, freelance"))
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to Working Hours")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text("Set up your first job so target and balance are right; change it later in Settings.")
                            .font(AppFont.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 8)
                }

                Section("Working time") {
                    LabeledContent("Target") {
                        PillTabs(
                            options: TargetMode.allCases.map { ($0, $0.title) },
                            selection: Binding(get: { job.targetMode }, set: { job.changeTargetMode(to: $0) })
                        )
                    }
                    switch job.targetMode {
                    case .daily:
                        LabeledContent("Per day") {
                            DurationField(minutes: $job.dailyTargetMinutes, range: 0...(16 * 60), step: 15)
                        }
                    case .weekly:
                        LabeledContent("Per week") {
                            DurationField(minutes: $job.weeklyTargetMinutes, range: 0...(80 * 60), step: 30)
                        }
                    }
                    LabeledContent("Workdays") {
                        WeekdayPicker(selection: $job.workdays)
                    }
                    LabeledContent("First day of work") {
                        ThemedDateField(date: Binding(
                            get: { job.startDate ?? Calendar.app.startOfDay(for: .now) },
                            set: { job.startDate = $0 }
                        ))
                    }
                    Toggle("Target only on tracked days", isOn: $job.targetOnlyOnTrackedDays)
                }

                Section {
                    LabeledContent("Holidays") {
                        Text(job.holidayRegion?.title ?? (settings.holidayDetectionDone ? String(localized: "Not detected") : String(localized: "Detecting…")))
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("From your system region; change it in Settings > Jobs > Holidays.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Divider()

            HStack {
                Spacer()
                Button("Get Started") {
                    finish()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if job.startDate == nil { job.startDate = Calendar.app.startOfDay(for: .now) }
        }
        .onDisappear(perform: finish)
    }

    private func finish() {
        guard !settings.onboardingDone else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { job.name = trimmed }
        settings.onboardingDone = true
        jobs.save()
        dismiss()
    }
}
