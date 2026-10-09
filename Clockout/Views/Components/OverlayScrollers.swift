import AppKit
import SwiftUI

extension View {
    /// Uses the thin overlay scrollbars that fade out when idle, even when macOS is set
    /// to always show scroll bars (e.g. with a mouse attached). Apply inside a ScrollView or
    /// List row, or directly on a Form.
    func overlayScrollers() -> some View {
        background(OverlayScrollerStyle())
    }
}

private struct OverlayScrollerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollerStyleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ScrollerStyleView: NSView {
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        applySoon()
        if observer == nil {
            // AppKit resets the style when the system preference changes.
            observer = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applySoon() }
            }
        }
    }

    private func applySoon() {
        DispatchQueue.main.async { [weak self] in
            guard let scrollView = self?.targetScrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
        }
    }

    private var targetScrollView: NSScrollView? {
        if let enclosingScrollView { return enclosingScrollView }
        // Applied to a Form from the outside: its scroll view is a sibling of this view.
        var ancestor = superview
        for _ in 0..<2 {
            if let found = ancestor.flatMap({ Self.firstScrollView(in: $0) }) { return found }
            ancestor = ancestor?.superview
        }
        return nil
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView { return scrollView }
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
}
