import AppIntents
import AppKit
import SwiftData
import SwiftUI
import UserNotifications

enum WindowID {
    static let main = "main"
}

@main
struct WorkingHoursApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: AppSettings
    @State private var jobs: JobStore
    @State private var tracker: TimeTracker
    @State private var awayDetector: AwayDetector
    private let container: ModelContainer

    init() {
        let container: ModelContainer
        do {
            #if DEBUG
            container = DemoData.isEnabled ? try DemoData.makeContainer() : try ModelContainer(for: WorkSession.self, Job.self)
            #else
            container = try ModelContainer(for: WorkSession.self, Job.self)
            #endif
        } catch {
            fatalError("The database could not be opened: \(error.localizedDescription)")
        }
        let settings = AppSettings()
        let jobs = JobStore(context: container.mainContext)
        self.container = container
        _settings = State(initialValue: settings)
        _jobs = State(initialValue: jobs)
        let tracker = TimeTracker(context: container.mainContext, settings: settings, jobs: jobs)
        _tracker = State(initialValue: tracker)
        _awayDetector = State(initialValue: AwayDetector(tracker: tracker, settings: settings))
        // Shortcuts and Siri act on the same tracker as the windows.
        AppDependencyManager.shared.add(dependency: tracker)
        AppDependencyManager.shared.add(dependency: jobs)
    }

    var body: some Scene {
        Window("Working Hours", id: WindowID.main) {
            ContentView()
                .background(MinimumAspectRatio(ratio: WindowLayout.minimumAspectRatio))
                .themedScene()
                .environment(tracker)
                .environment(jobs)
                .environment(settings)
                .environment(\.locale, .app)
        }
        .modelContainer(container)
        .defaultSize(width: 1260, height: 857)
        .commands {
            TrackerCommands(tracker: tracker, jobs: jobs)
        }

        MenuBarExtra(isInserted: $settings.showMenuBarExtra) {
            MenuBarView()
                .themedScene()
                .environment(tracker)
                .environment(jobs)
                .environment(settings)
                .environment(\.locale, .app)
                .modelContainer(container)
        } label: {
            MenuBarLabel(tracker: tracker)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .themedScene(rebuildsOnAccentChange: false)
                .environment(tracker)
                .environment(jobs)
                .environment(settings)
                .environment(\.locale, .app)
                .modelContainer(container)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let window, MenuBarMode.isRegular(window) else { return }
                MenuBarMode.updateActivationPolicy(closing: window)
            }
        }
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let window, MenuBarMode.isRegular(window), NSApp.activationPolicy() != .regular else { return }
                MenuBarMode.showApp()
            }
        }
    }

    /// With the menu bar item visible the app keeps running when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MenuBarMode.isEnabled
    }

    /// Quitting from the Dock or with Command-Q leaves the timer in the menu bar.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard MenuBarMode.isEnabled, !MenuBarMode.quitsCompletely, !MenuBarMode.isSystemQuit else { return .terminateNow }
        for window in NSApp.windows where window.isVisible && MenuBarMode.isRegular(window) {
            window.close()
        }
        NSApp.setActivationPolicy(.accessory)
        return .terminateCancel
    }

    /// Clicking the Dock icon or opening the app again while it only lives in the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MenuBarMode.showApp()
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

struct TrackerCommands: Commands {
    let tracker: TimeTracker
    let jobs: JobStore

    var body: some Commands {
        CommandMenu("Time Tracking") {
            Button("\(tracker.primaryActionTitle(for: jobs.currentJob)): \(jobs.currentJob.displayName)") {
                tracker.togglePrimary(for: jobs.currentJob)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Finish Day") {
                tracker.stop()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(tracker.status == .idle)

            Divider()

            Section("Job") {
                ForEach(Array(jobs.jobs.prefix(9).enumerated()), id: \.element.uuid) { index, job in
                    Toggle(job.displayName, isOn: Binding(get: { jobs.currentJob === job }, set: { _ in jobs.select(job) }))
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }
    }
}
