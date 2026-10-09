import SwiftUI

/// Marks a single day as vacation, sick day or public holiday.
struct AbsenceButton: View {
    let job: Job
    let day: Date

    @Environment(JobStore.self) private var jobs
    @State private var showsMenu = false

    var body: some View {
        let current = job.absence(on: day)

        Button {
            showsMenu = true
        } label: {
            Label(current?.title ?? String(localized: "Absence"), systemImage: current?.systemImage ?? "calendar.badge.minus")
        }
        .buttonStyle(.secondary(height: 28))
        .help("Mark as day off")
        .popover(isPresented: $showsMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(AbsenceKind.allCases) { kind in
                    MenuRow(action: { set(kind) }) {
                        Image(systemName: kind.systemImage)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text(kind.title)
                        Spacer(minLength: 12)
                        if current == kind {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.brand)
                        }
                    }
                }

                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 1)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)

                MenuRow(action: { set(nil) }) {
                    Image(systemName: "xmark")
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text("No Absence")
                    Spacer()
                }
                .disabled(current == nil)
            }
            .padding(6)
            .frame(width: 220)
            .background(Color.surface)
            .presentationBackground(Color.surface)
        }
    }

    private func set(_ kind: AbsenceKind?) {
        job.setAbsence(kind, on: [day])
        jobs.save()
        showsMenu = false
    }
}

/// Enters vacation or sick leave for a range of days at once.
struct AbsenceSheet: View {
    let job: Job

    @Environment(\.dismiss) private var dismiss
    @Environment(JobStore.self) private var jobs

    @State private var kind: AbsenceKind = .vacation
    @State private var from: Date
    @State private var to: Date
    @State private var onlyWorkdays = true

    /// Longer ranges are cut off so a typo in the year cannot create thousands of entries.
    private static let maximumDays = 366

    init(job: Job, day: Date) {
        self.job = job
        _from = State(initialValue: day)
        _to = State(initialValue: day)
    }

    private var allDays: [Date] {
        let calendar = Calendar.app
        var day = calendar.startOfDay(for: min(from, to))
        let last = calendar.startOfDay(for: max(from, to))
        var result: [Date] = []
        while day <= last, result.count < Self.maximumDays {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private var selectedDays: [Date] {
        let rules = job.rules
        return onlyWorkdays ? allDays.filter { rules.isWorkday($0) && rules.holiday(on: $0) == nil } : allDays
    }

    var body: some View {
        let days = selectedDays

        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Type") {
                        PillTabs(options: AbsenceKind.allCases.map { ($0, $0.title) }, selection: $kind)
                    }
                    LabeledContent("From") {
                        ThemedDateField(date: $from)
                    }
                    LabeledContent("To") {
                        ThemedDateField(date: $to)
                    }
                    Toggle("Workdays only", isOn: $onlyWorkdays)
                } header: {
                    Text("Absence for \(job.displayName)")
                } footer: {
                    Text("\(days.count) days without target; work on them still counts.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Divider()

            HStack {
                Button("Clear Range") {
                    job.setAbsence(nil, on: allDays)
                    jobs.save()
                    dismiss()
                }
                .help("Remove all absences in this range")
                .disabled(!allDays.contains { job.absence(on: $0) != nil })
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add Absence") {
                    job.setAbsence(kind, on: days)
                    jobs.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(days.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
