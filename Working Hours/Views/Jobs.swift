import SwiftUI

/// Sidebar header to switch between jobs, like a workspace switcher.
struct JobSwitcher: View {
    @Environment(JobStore.self) private var jobs
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab: SettingsTab = .general
    @State private var isOpen = false
    @State private var showsNewJob = false

    var body: some View {
        let current = jobs.currentJob

        // A themed popover instead of a native menu: AppKit draws menu highlights in the
        // app's built-in accent, which ignores the chosen theme.
        Button {
            isOpen.toggle()
        } label: {
            JobSwitcherLabel(current: current, otherActive: tracker.activeJob.flatMap { $0 === current ? nil : $0 })
        }
        .buttonStyle(.plain)
        .help("Switch job (⌘1 to ⌘9)")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            JobSwitcherMenu(
                onSelect: { job in
                    jobs.select(job)
                    isOpen = false
                },
                onNewJob: {
                    isOpen = false
                    showsNewJob = true
                },
                onManage: {
                    isOpen = false
                    settingsTab = .jobs
                    openSettings()
                }
            )
        }
        .sheet(isPresented: $showsNewJob) {
            NewJobSheet()
        }
    }
}

private struct JobSwitcherMenu: View {
    let onSelect: (Job) -> Void
    let onNewJob: () -> Void
    let onManage: () -> Void

    @Environment(JobStore.self) private var jobs
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Jobs")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 3)

            ForEach(Array(jobs.jobs.enumerated()), id: \.element.uuid) { index, job in
                MenuRow(action: { onSelect(job) }) {
                    JobIcon(job: job, size: 18)
                    Text(job.displayName)
                        .lineLimit(1)
                    if tracker.activeJob === job {
                        Circle()
                            .fill(tracker.status(for: job).tint)
                            .frame(width: 6, height: 6)
                            .help(tracker.status(for: job).title)
                    }
                    Spacer(minLength: 12)
                    if job === jobs.currentJob {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.brand)
                    } else if index < 9 {
                        Text("⌘\(index + 1)")
                            .font(AppFont.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)

            MenuRow(action: onNewJob) {
                Image(systemName: "plus")
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text("New Job…")
                Spacer()
            }
            MenuRow(action: onManage) {
                Image(systemName: "gearshape")
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text("Manage Jobs…")
                Spacer()
            }
        }
        .padding(6)
        .frame(width: 250)
        .background(Color.surface)
        .presentationBackground(Color.surface)
    }
}

/// One clickable line in a themed menu, with a neutral hover highlight.
struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                content
            }
            .font(AppFont.body)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                Color.primary.opacity(isHovered ? 0.07 : 0),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct JobSwitcherLabel: View {
    let current: Job
    let otherActive: Job?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            JobIcon(job: current, size: 22)
            Text(current.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let otherActive {
                JobIcon(job: otherActive, size: 14)
                    .help(Text("\(otherActive.displayName) is running"))
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(
            Color.primary.opacity(isHovered ? 0.06 : 0),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct NewJobSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JobStore.self) private var jobs

    @State private var name = ""
    @State private var color: JobColor = .blue
    @State private var copiesRules = false
    @State private var iconData: Data?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("e.g. student job, mini job, freelance"))
                    LabeledContent("Picture") {
                        JobIconPicker(data: $iconData, color: color, name: name.isEmpty ? "?" : name)
                    }
                    // The color only matters for the initial shown when there is no picture.
                    if iconData == nil {
                        LabeledContent("Color") {
                            JobColorPicker(selection: $color)
                        }
                    }
                } header: {
                    Text("New Job")
                }
                Section {
                    Toggle("Copy rules from “\(jobs.currentJob.displayName)”", isOn: $copiesRules)
                } footer: {
                    Text("Target, workdays, rounding and break format. Without copying, 8 hours from Monday to Friday apply. You can change everything later in Settings under Jobs.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let job = jobs.addJob(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        color: color,
                        copyingRulesFrom: copiesRules ? jobs.currentJob : nil
                    )
                    job.iconData = iconData
                    jobs.select(job)
                    jobs.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { color = jobs.nextColor }
    }
}

/// Shown on a job's pages while the timer runs for a different job.
struct OtherJobRunningBanner: View {
    let job: Job

    @Environment(TimeTracker.self) private var tracker
    @Environment(JobStore.self) private var jobs

    var body: some View {
        if let active = tracker.activeJob, active !== job {
            HStack(spacing: 10) {
                JobIcon(job: active, size: 18)
                Text(text(for: active))
                    .font(AppFont.body)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Switch to \(active.displayName)") {
                    jobs.select(active)
                }
                .buttonStyle(.secondary(height: 26))
            }
            .card(padding: 10)
        }
    }

    private func text(for active: Job) -> String {
        switch tracker.status(for: active) {
        case .working:
            return String(localized: "The timer is running for \(active.displayName) (\(tracker.currentBlockDuration.stopwatch)). Starting here ends that block.")
        case .onBreak:
            return String(localized: "\(active.displayName) is on a break (\(tracker.currentBreakDuration.stopwatch)).")
        case .idle:
            return ""
        }
    }
}
