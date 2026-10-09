import SwiftUI

/// Public holidays of one job: on or off, the region, and single holidays that still count as workdays.
struct HolidaySettingsView: View {
    @Bindable var job: Job

    @State private var isDetecting = false
    @State private var detectionNote: String?

    private var year: Int { Calendar.app.component(.year, from: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(footer: "Holidays have no target; hours tracked on them still count.") {
                SettingsToggle(title: "Public holidays", isOn: $job.holidaysEnabled)
                if job.holidaysEnabled {
                    SettingsRow(title: "Country", subtitle: detectionNote.map { LocalizedStringResource("\($0)") }) {
                        HStack(spacing: 8) {
                            Button {
                                detect()
                            } label: {
                                if isDetecting {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Use Location", systemImage: "location")
                                }
                            }
                            .buttonStyle(.secondary(height: 26))
                            .disabled(isDetecting)

                            Picker("Country", selection: countryBinding) {
                                Text("None").tag(HolidayCountry?.none)
                                ForEach(HolidayCountry.allCases) { country in
                                    Text(country.title).tag(HolidayCountry?.some(country))
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                    if job.holidayRegion?.country == .germany {
                        SettingsRow(title: "State") {
                            Picker("State", selection: stateBinding) {
                                Text("Nationwide only").tag(GermanState?.none)
                                ForEach(GermanState.allCases) { state in
                                    Text(state.title).tag(GermanState?.some(state))
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }

            if job.holidaysEnabled, let region = job.holidayRegion {
                HolidayList(job: job, region: region, year: year)
            }
        }
    }

    private var countryBinding: Binding<HolidayCountry?> {
        Binding(
            get: { job.holidayRegion?.country },
            set: { country in
                job.holidayRegion = country.map { HolidayRegion(country: $0, state: job.holidayRegion?.state) }
                detectionNote = nil
            }
        )
    }

    private var stateBinding: Binding<GermanState?> {
        Binding(
            get: { job.holidayRegion?.state },
            set: { state in
                job.holidayRegion = HolidayRegion(country: .germany, state: state)
                detectionNote = nil
            }
        )
    }

    private func detect() {
        isDetecting = true
        Task {
            let result = await RegionDetector().detect()
            isDetecting = false
            if let region = result.region {
                job.holidayRegion = region
                detectionNote = result.fromLocation ? String(localized: "From your location") : String(localized: "From System Settings")
            } else {
                detectionNote = String(localized: "Not detected. Choose a country.")
            }
        }
    }
}

/// This year's holidays with a switch each. Switched off ones count as normal days.
private struct HolidayList: View {
    @Bindable var job: Job
    let region: HolidayRegion
    let year: Int

    var body: some View {
        let holidays = HolidayCalendar.holidays(in: year, region: region).values.sorted { $0.date < $1.date }

        VStack(alignment: .leading, spacing: 8) {
            Text("Holidays \(String(year)) in \(region.title)")
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(holidays, id: \.kind) { holiday in
                        HStack(spacing: 12) {
                            Text(holiday.date.formatted(.dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits).locale(.app)))
                                .font(AppFont.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(holiday.title)
                                .font(AppFont.body)
                            Spacer()
                            Toggle(holiday.title, isOn: binding(for: holiday.kind))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .opacity(job.ignoredHolidays.contains(holiday.kind) ? 0.5 : 1)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
            .card(padding: 0)
        }
    }

    private func binding(for kind: HolidayKind) -> Binding<Bool> {
        Binding(
            get: { !job.ignoredHolidays.contains(kind) },
            set: { isOn in
                var ignored = job.ignoredHolidays
                if isOn { ignored.remove(kind) } else { ignored.insert(kind) }
                job.ignoredHolidays = ignored
            }
        )
    }
}
