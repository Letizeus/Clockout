import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case jobs
    case reminders
    case data

    /// Stored so other places (e.g. "Manage Jobs…") can open a specific tab.
    static let storageKey = "settingsTab"

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .jobs: String(localized: "Jobs")
        case .reminders: String(localized: "Reminders")
        case .data: String(localized: "Data")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .jobs: "briefcase"
        case .reminders: "bell.badge"
        case .data: "externaldrive"
        }
    }
}

/// The settings window, drawn entirely in theme colors (the native tab bar ignores the app's accent).
struct SettingsView: View {
    @AppStorage(SettingsTab.storageKey) private var selection: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsTabButton(tab: tab)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)

            // One fixed window size for every tab, so switching tabs never resizes the window.
            ScrollView {
                Group {
                    switch selection {
                    case .general: GeneralSettingsView()
                    case .appearance: AppearanceSettingsView()
                    case .jobs: JobsSettingsView()
                    case .reminders: ReminderSettingsView()
                    case .data: DataSettingsView()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .overlayScrollers()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 720, height: 744)
        .background(Color.canvas)
        .containerBackground(Color.canvas, for: .window)
        .navigationTitle(selection.title)
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab

    // Each button reads the selection itself, so its highlight always follows the stored value.
    @AppStorage(SettingsTab.storageKey) private var selection: SettingsTab = .general
    @State private var isHovered = false

    private var isSelected: Bool { selection == tab }

    var body: some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 16, weight: .regular))
                    .frame(height: 20)
                Text(tab.title)
                    .font(AppFont.caption)
            }
            .foregroundStyle(isSelected ? Color.brand : Color.secondary)
            .frame(width: 92, height: 50)
            .background(
                Color.primary.opacity(isSelected ? 0.07 : (isHovered ? 0.04 : 0)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: General

private struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(
                title: "Startup",
                footer: settings.showMenuBarExtra
                    ? "When you quit, the timer stays in the menu bar. To quit completely, use the power button there."
                    : nil
            ) {
                LaunchAtLoginToggle()
                SettingsToggle(title: "Show timer in the menu bar", isOn: $settings.showMenuBarExtra)
            }

            SettingsSection(
                title: "Hints",
                footer: "Target, workdays, rounding and the break format are set per job under Jobs."
            ) {
                SettingsToggle(title: "Warn about breaks and maximum hours (German ArbZG)", isOn: $settings.showsComplianceHints)
            }
        }
    }
}

// MARK: Jobs

private struct JobsSettingsView: View {
    @Environment(JobStore.self) private var jobs
    @Environment(TimeTracker.self) private var tracker
    @State private var selectedID: UUID?
    @State private var pendingDeletion: Job?

    var body: some View {
        let selected = jobs.job(withID: selectedID) ?? jobs.currentJob

        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Jobs")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)

                VStack(spacing: 2) {
                    ForEach(Array(jobs.jobs.enumerated()), id: \.element.uuid) { index, job in
                        JobListRow(job: job, isSelected: job === selected) {
                            selectedID = job.uuid
                        }
                        .contextMenu {
                            Button("Move Up") { jobs.move(fromOffsets: [index], toOffset: index - 1) }
                                .disabled(index == 0)
                            Button("Move Down") { jobs.move(fromOffsets: [index], toOffset: index + 2) }
                                .disabled(index == jobs.jobs.count - 1)
                            Divider()
                            Button("Delete…", role: .destructive) { pendingDeletion = job }
                                .disabled(jobs.jobs.count < 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(maxHeight: .infinity, alignment: .top)
                .card(padding: 0)

                HStack(spacing: 2) {
                    Button {
                        let job = jobs.addJob(name: String(localized: "New job"), color: jobs.nextColor)
                        selectedID = job.uuid
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add Job")
                    Button {
                        pendingDeletion = selected
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(jobs.jobs.count < 2)
                    .help(jobs.jobs.count < 2 ? "The last job cannot be deleted" : "Delete Job")
                }
                .buttonStyle(.ghost)
            }
            .frame(width: 180)

            JobEditor(job: selected)
                .id(selected.uuid)
        }
        .frame(height: JobEditor.height)
        .onAppear { selectedID = jobs.currentJob.uuid }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.displayName ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { job in
            Button("Delete Job and Entries", role: .destructive) {
                tracker.deleteJob(job)
                selectedID = jobs.currentJob.uuid
            }
        } message: { job in
            Text("The job and its \(tracker.sessions(of: job).count) work blocks will be deleted permanently. Export the times in History first if you want to keep them.")
        }
    }
}

private struct JobListRow: View {
    let job: Job
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                JobIcon(job: job, size: 18)
                Text(job.displayName)
                    .font(AppFont.bodyMedium)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                Color.primary.opacity(isSelected ? 0.08 : (isHovered ? 0.04 : 0)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Name, picture and working time rules of one job, split into small pages.
private struct JobEditor: View {
    static let height: CGFloat = 520

    @Bindable var job: Job

    enum Page: String, CaseIterable {
        case general
        case workTime
        case holidays
        case balance
        case timesheet

        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .workTime: String(localized: "Working time")
            case .holidays: String(localized: "Holidays")
            case .balance: String(localized: "Balance")
            case .timesheet: String(localized: "Timesheet")
            }
        }
    }

    @AppStorage("jobEditorPage") private var page: Page = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PillTabs(options: Page.allCases.map { ($0, $0.title) }, selection: $page)

            switch page {
            case .general:
                SettingsSection {
                    SettingsRow(title: "Name") {
                        ThemedTextField(placeholder: "e.g. Student job", text: $job.name)
                    }
                    SettingsRow(title: "Picture") {
                        JobIconPicker(data: $job.iconData, color: job.color, name: job.displayName)
                            .frame(maxWidth: 300)
                    }
                    // The color only matters for the initial shown when there is no picture.
                    if job.iconData == nil {
                        SettingsRow(title: "Color") {
                            JobColorPicker(selection: $job.color)
                        }
                    }
                }

            case .workTime:
                SettingsSection(footer: "Otherwise a workday without entries counts as minus hours. Before the first day of work, on holidays and on absence days from History there is no target.") {
                    SettingsRow(title: "Enter target") {
                        PillTabs(
                            options: TargetMode.allCases.map { ($0, $0.title) },
                            selection: Binding(get: { job.targetMode }, set: { job.changeTargetMode(to: $0) })
                        )
                    }
                    switch job.targetMode {
                    case .daily:
                        SettingsRow(title: "Target hours per day", subtitle: "Weekly target \(job.weeklyTarget.clock) h") {
                            DurationField(minutes: $job.dailyTargetMinutes, range: 0...(16 * 60), step: 15)
                        }
                    case .weekly:
                        SettingsRow(
                            title: "Target hours per week",
                            subtitle: job.workdays.isEmpty ? nil : "\(job.dailyTarget.clock) h per workday"
                        ) {
                            DurationField(minutes: $job.weeklyTargetMinutes, range: 0...(80 * 60), step: 30)
                        }
                    }
                    SettingsRow(title: "Workdays") {
                        WeekdayPicker(selection: $job.workdays)
                    }
                    SettingsToggle(title: "Target only on days with entries", isOn: $job.targetOnlyOnTrackedDays)
                    StartDateRow(job: job)
                }

            case .holidays:
                HolidaySettingsView(job: job)

            case .balance:
                SettingsSection(footer: CarryOverText.footer) {
                    CarryOverFields(job: job)
                }

            case .timesheet:
                SettingsSection(footer: "Start, working time and break are rounded to the nearest step; the end follows from them.") {
                    SettingsRow(title: "Rounding") {
                        Picker("Rounding", selection: $job.roundingMinutes) {
                            Text("Exact to the minute").tag(1)
                            Text("5 minutes").tag(5)
                            Text("10 minutes").tag(10)
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsRow(title: "Enter break as") {
                        Picker("Enter break as", selection: $job.breakFormat) {
                            ForEach(BreakFormat.allCases) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Reminders

private struct ReminderSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TimeTracker.self) private var tracker
    @State private var permissionDenied = false

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 20) {
            SettingsSection {
                SettingsToggle(
                    title: "Enable notifications",
                    isOn: Binding(get: { settings.remindersEnabled }, set: { setRemindersEnabled($0) })
                )
                if permissionDenied {
                    SettingsNotice(systemImage: "exclamationmark.triangle", text: "Notifications are turned off in System Settings.")
                }
            }

            SettingsSection(footer: "German law requires a break after 6 hours of work at the latest. The reminder refers to the current work block.") {
                SettingsRow(title: "Break reminder") {
                    Picker("Break reminder", selection: $settings.breakReminderMinutes) {
                        Text("Off").tag(0)
                        ForEach([240, 270, 300, 330, 360], id: \.self) { minutes in
                            Text("after \(TimeInterval(minutes * 60).clock) h straight").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsToggle(title: "Notify when the target is reached", isOn: $settings.targetReminderEnabled)
            }
            .disabled(!settings.remindersEnabled)
            .opacity(settings.remindersEnabled ? 1 : 0.5)

            SettingsSection(footer: "If the timer runs while nobody uses the Mac or it sleeps, the app asks on your return whether the time was a break. With notifications also when the window is closed.") {
                SettingsRow(title: "Detect time away") {
                    Picker("Detect time away", selection: $settings.awayDetectionMinutes) {
                        Text("Off").tag(0)
                        ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text("after \(minutes) minutes").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .onChange(of: settings.breakReminderMinutes) { tracker.rescheduleReminders() }
        .onChange(of: settings.targetReminderEnabled) { tracker.rescheduleReminders() }
    }

    private func setRemindersEnabled(_ enabled: Bool) {
        guard enabled else {
            settings.remindersEnabled = false
            tracker.rescheduleReminders()
            return
        }
        Task {
            let granted = await ReminderScheduler.requestAuthorization()
            settings.remindersEnabled = granted
            permissionDenied = !granted
            tracker.rescheduleReminders()
        }
    }
}

// MARK: Data

private struct DataSettingsView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(JobStore.self) private var jobs
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkSession.start) private var sessions: [WorkSession]
    @State private var confirmsDeletion = false
    @State private var backupDocument: BackupDocument?
    @State private var showsBackupExporter = false
    @State private var showsBackupImporter = false
    @State private var pendingRestore: Backup?
    @State private var backupMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Stored Data") {
                ForEach(jobs.jobs, id: \.uuid) { job in
                    let count = sessions.filter { $0.jobID == job.uuid }.count
                    SettingsRow(title: "\(job.displayName)") {
                        Text("\(count) work blocks")
                            .font(AppFont.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsRow(title: "First entry") {
                    Text(sessions.first?.start.numericDate ?? "-")
                        .font(AppFont.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                SettingsRow(title: "Storage location") {
                    Text("Locally on this Mac")
                        .font(AppFont.body)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection(
                title: "Backup",
                footer: backupMessage.map { LocalizedStringResource("\($0)") } ?? "Contains all jobs with their rules, pictures, absences, carry-over and entries. Use it to move to a new Mac, too. Restoring replaces the current data."
            ) {
                SettingsRow(title: "Create backup") {
                    Button("Save…", action: exportBackup)
                        .buttonStyle(.secondary(height: 26))
                }
                SettingsRow(title: "Restore backup") {
                    Button("Open…") { showsBackupImporter = true }
                        .buttonStyle(.secondary(height: 26))
                }
            }

            SettingsSection(footer: "Create a backup first or export your times as CSV in History if you want to keep them.") {
                SettingsRow(title: "Delete all entries of all jobs") {
                    Button {
                        confirmsDeletion = true
                    } label: {
                        Text("Delete All Data…")
                            .foregroundStyle(Color.negative)
                    }
                    .buttonStyle(.secondary(height: 26))
                    .disabled(sessions.isEmpty)
                }
            }
        }
        .fileExporter(
            isPresented: $showsBackupExporter,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "Working Hours Backup \(Date.now.formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result { backupMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showsBackupImporter, allowedContentTypes: [.json]) { result in
            do {
                pendingRestore = try Backup.read(from: result.get())
            } catch {
                backupMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Restore backup?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { backup in
            Button("Restore", role: .destructive) { restore(backup) }
        } message: { backup in
            let jobCount = String(localized: "\(backup.jobs.count) jobs")
            let blockCount = String(localized: "\(backup.sessions.count) work blocks")
            Text("Backup from \(backup.createdAt.numericDate): \(jobCount), \(blockCount). This replaces all current jobs and entries.")
        }
        .confirmationDialog("Delete all entries?", isPresented: $confirmsDeletion) {
            Button("Delete All", role: .destructive) {
                tracker.deleteAllData()
            }
        } message: {
            Text("\(sessions.count) work blocks of all jobs will be removed permanently. The jobs and their rules are kept. This cannot be undone.")
        }
    }

    private func exportBackup() {
        do {
            let backup = Backup(jobs: jobs.jobs, sessions: sessions, currentJobID: jobs.currentJob.uuid)
            backupDocument = BackupDocument(data: try backup.encoded())
            backupMessage = nil
            showsBackupExporter = true
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    private func restore(_ backup: Backup) {
        do {
            try backup.restore(into: context, tracker: tracker, jobStore: jobs)
            backupMessage = String(localized: "Backup from \(backup.createdAt.numericDate) restored.")
        } catch {
            backupMessage = String(localized: "Restoring failed: \(error.localizedDescription)")
        }
    }
}

/// First day of the job. Before it no target counts, so starting mid-year does not show minus hours.
private struct StartDateRow: View {
    @Bindable var job: Job

    @Query(sort: \WorkSession.start) private var sessions: [WorkSession]

    var body: some View {
        SettingsRow(title: "First day of work", subtitle: job.startDate == nil ? "Not set" : nil) {
            if let startDate = job.startDate {
                ThemedDateField(
                    date: Binding(get: { startDate }, set: { job.startDate = $0 }),
                    onClear: { job.startDate = nil }
                )
            } else {
                Button("Set") {
                    let first = sessions.first { $0.jobID == job.uuid }?.start ?? .now
                    job.startDate = Calendar.app.startOfDay(for: first)
                }
                .buttonStyle(.secondary(height: 26))
            }
        }
    }
}
