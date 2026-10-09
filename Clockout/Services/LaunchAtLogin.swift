import OSLog
import ServiceManagement
import SwiftUI

/// Registers the app as a login item (System Settings > General > Login Items).
struct LaunchAtLoginToggle: View {
    @State private var isEnabled = false
    @State private var requiresApproval = false
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: "Clockout", category: "LaunchAtLogin")

    var body: some View {
        SettingsToggle(title: "Open at login", isOn: Binding(get: { isEnabled }, set: setEnabled))
            .onAppear(perform: refresh)
            // The user can change login items in System Settings while the app runs.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refresh()
            }

        if requiresApproval {
            SettingsRow(title: "Needs approval in System Settings") {
                Button("Open Login Items") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .buttonStyle(.secondary(height: 26))
            }
        }
        if let errorMessage {
            SettingsNotice(systemImage: "exclamationmark.triangle", tint: .negative, text: "\(errorMessage)")
        }
    }

    private func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            logger.error("Changing login item failed: \(error.localizedDescription)")
            errorMessage = String(localized: "Couldn’t change the login item: \(error.localizedDescription)")
        }
        refresh()
    }
}
