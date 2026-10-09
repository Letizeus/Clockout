import SwiftData
import SwiftUI

enum SessionEditorTarget: Identifiable {
    case edit(WorkSession)
    case create(day: Date, job: Job)

    var id: AnyHashable {
        switch self {
        case .edit(let session): AnyHashable(session.persistentModelID)
        case .create(let day, let job): AnyHashable("\(job.uuid)-\(day.timeIntervalSince1970)")
        }
    }
}

struct SessionEditorView: View {
    let target: SessionEditorTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TimeTracker.self) private var tracker
    @Environment(JobStore.self) private var jobs

    @State private var start: Date
    @State private var end: Date
    @State private var isRunning: Bool
    @State private var note: String
    @State private var jobID: UUID?
    @State private var confirmsDeletion = false

    init(target: SessionEditorTarget) {
        self.target = target
        switch target {
        case .edit(let session):
            _start = State(initialValue: session.start)
            _end = State(initialValue: session.end ?? .now)
            _isRunning = State(initialValue: session.isRunning)
            _note = State(initialValue: session.note)
            _jobID = State(initialValue: session.jobID)
        case .create(let day, let job):
            _jobID = State(initialValue: job.uuid)
            let calendar = Calendar.app
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            _start = State(initialValue: start)
            _end = State(initialValue: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? start)
            _isRunning = State(initialValue: false)
            _note = State(initialValue: "")
        }
    }

    private var isEditingRunningSession: Bool {
        if case .edit(let session) = target { return session.isRunning }
        return false
    }

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

    private var duration: TimeInterval {
        (isRunning ? Date.now : end).timeIntervalSince(start)
    }

    private var validationMessage: String? {
        if isRunning {
            return start > .now ? String(localized: "Start can’t be in the future") : nil
        }
        if end <= start { return String(localized: "End must be after start") }
        if duration > 24 * 3600 { return String(localized: "A work block can’t exceed 24 hours") }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Start time") {
                        ThemedDateTimeField(date: $start)
                    }
                    if isEditingRunningSession {
                        Toggle("Still running", isOn: $isRunning)
                    }
                    if !isRunning {
                        LabeledContent("End time") {
                            ThemedDateTimeField(date: $end)
                        }
                    }
                    LabeledContent("Duration") {
                        Text(duration > 0 ? "\(duration.clock) h" : "-")
                            .monospacedDigit()
                    }
                } header: {
                    Text(isEditing ? "Edit Work Block" : "Add Work Block")
                }

                if jobs.jobs.count > 1 {
                    Section {
                        Picker("Job", selection: Binding(get: { jobID ?? jobs.currentJob.uuid }, set: { jobID = $0 })) {
                            ForEach(jobs.jobs, id: \.uuid) { job in
                                Text(job.displayName).tag(job.uuid)
                            }
                        }
                    }
                }

                Section("Note") {
                    TextField("Note", text: $note, prompt: Text("e.g. project or task"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...4)
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.negative)
                }
            }
            .formStyle(.grouped)
            .overlayScrollers()
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            HStack {
                if isEditing {
                    Button("Delete…", role: .destructive) {
                        confirmsDeletion = true
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil)
            }
            .padding(16)
        }
        .frame(width: 460)
        .confirmationDialog("Delete Work Block?", isPresented: $confirmsDeletion) {
            Button("Delete Work Block", role: .destructive) {
                if case .edit(let session) = target {
                    tracker.delete(session)
                }
                dismiss()
            }
        } message: {
            Text("This can’t be undone.")
        }
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch target {
        case .edit(let session):
            session.start = start
            session.end = isRunning ? nil : end
            session.note = trimmedNote
            session.jobID = jobID ?? jobs.currentJob.uuid
        case .create:
            context.insert(WorkSession(start: start, end: end, note: trimmedNote, jobID: jobID ?? jobs.currentJob.uuid))
        }
        tracker.sessionsDidChange()
        dismiss()
    }
}
