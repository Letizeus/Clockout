import AppKit

/// While the timer is shown in the menu bar, quitting only closes the windows and hides the Dock icon.
/// The app then keeps running in the menu bar until it is quit from there.
enum MenuBarMode {
    /// Set by the power button in the menu bar, which really quits.
    static var quitsCompletely = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: AppSettings.Key.showMenuBarExtra) as? Bool ?? true
    }

    static func quit() {
        quitsCompletely = true
        NSApp.terminate(nil)
    }

    /// Brings back the Dock icon and the window, e.g. from the menu bar.
    static func showApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Dock icon while a regular window is open, menu bar only otherwise.
    static func updateActivationPolicy(closing: NSWindow? = nil) {
        guard isEnabled else {
            NSApp.setActivationPolicy(.regular)
            return
        }
        let hasWindow = NSApp.windows.contains { window in
            window !== closing && window.isVisible && isRegular(window)
        }
        NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
    }

    /// Logout, restart and shutdown send a quit event with a reason. Those always quit.
    static var isSystemQuit: Bool {
        let quitReason = AEKeyword(0x7768_793F) // 'why?'
        return NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: quitReason) != nil
    }

    /// Main and settings windows, not the menu bar panel or popovers.
    static func isRegular(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.canBecomeMain
    }
}
