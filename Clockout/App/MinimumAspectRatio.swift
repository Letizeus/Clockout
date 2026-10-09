import AppKit
import SwiftUI

enum WindowLayout {
    /// Minimum content size below the toolbar.
    static let minWidth: CGFloat = 1100
    static let minHeight: CGFloat = 696
    /// Height of the unified toolbar, so the smallest window frame is 1100 x 748.
    static let toolbarHeight: CGFloat = 52
    /// Width to height of the whole window frame. It may get wider, never closer to a square.
    static let minimumAspectRatio: CGFloat = 1.47
}

/// Sets the minimum content size and caps the window height at `width / ratio` by keeping
/// `NSWindow.maxSize` in sync with the width.
///
/// The minimum lives on the window instead of a SwiftUI `.frame(minWidth:)`: around a
/// `NavigationSplitView` that frame keeps the detail column from shrinking while the sidebar
/// slides in, so the content jumps into place at the end of the animation.
struct MinimumAspectRatio: NSViewRepresentable {
    let ratio: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(ratio: ratio)
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowObservingView()
        let coordinator = context.coordinator
        view.onWindowChange = { coordinator.attach(to: $0) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private let ratio: CGFloat
        private weak var window: NSWindow?
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

        init(ratio: CGFloat) {
            self.ratio = ratio
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func attach(to window: NSWindow?) {
            guard let window, window !== self.window else { return }
            observers.forEach(NotificationCenter.default.removeObserver)
            self.window = window

            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.update() }
                },
                center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak window] _ in
                    MainActor.assumeIsolated {
                        window?.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                    }
                },
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.update() }
                },
            ]
            update()
            #if DEBUG
            // Launch with `-minimumWindow` to check the layout at the smallest size.
            if ProcessInfo.processInfo.arguments.contains("-minimumWindow") {
                window.setFrame(NSRect(origin: window.frame.origin, size: window.minSize), display: true)
            }
            #endif
        }

        private func update() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            let minimum = NSSize(width: WindowLayout.minWidth, height: WindowLayout.minHeight + WindowLayout.toolbarHeight)
            if window.minSize != minimum {
                window.minSize = minimum
            }
            if !window.inLiveResize && (window.frame.width < minimum.width - 0.5 || window.frame.height < minimum.height - 0.5) {
                var frame = window.frame
                let height = max(frame.height, minimum.height)
                frame.origin.y -= height - frame.height
                frame.size = NSSize(width: max(frame.width, minimum.width), height: height)
                window.setFrame(frame, display: true)
            }
            let maxHeight = max(window.minSize.height, window.frame.width / ratio)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: maxHeight)

            // A restored or programmatic frame can still be too tall; shrink it, keeping the top edge.
            if !window.inLiveResize && window.frame.height > maxHeight + 0.5 {
                var frame = window.frame
                frame.origin.y += frame.height - maxHeight
                frame.size.height = maxHeight
                window.setFrame(frame, display: true)
            }
        }
    }
}

private final class WindowObservingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
