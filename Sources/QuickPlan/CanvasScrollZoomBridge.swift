#if os(macOS)
import AppKit
import SwiftUI

/// Observes wheel events over the canvas without becoming a mouse hit target.
@MainActor
struct CanvasScrollZoomBridge: NSViewRepresentable {
    var onScroll: @MainActor (Double, CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollZoomView {
        ScrollZoomView(onScroll: onScroll)
    }

    func updateNSView(_ nsView: ScrollZoomView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: ScrollZoomView, coordinator: ()) {
        nsView.removeScrollMonitor()
    }

    final class ScrollZoomView: NSView {
        var onScroll: @MainActor (Double, CGPoint) -> Void
        private var scrollMonitor: Any?

        init(onScroll: @escaping @MainActor (Double, CGPoint) -> Void) {
            self.onScroll = onScroll
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { return nil }

        // The canvas uses a top-left origin, matching SwiftUI's local points.
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeScrollMonitor()
            guard window != nil else { return }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // AppKit invokes local event monitors on its main event loop.
                // Return only a Sendable Bool across the isolation assertion.
                let consumed = MainActor.assumeIsolated {
                    self?.handleScroll(event) ?? false
                }
                return consumed ? nil : event
            }
        }

        func removeScrollMonitor() {
            guard let scrollMonitor else { return }
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }

        private func handleScroll(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, !isHiddenOrHasHiddenAncestor else { return false }
            let location = convert(event.locationInWindow, from: nil)
            let delta = Double(event.scrollingDeltaY)
            guard bounds.contains(location), delta.isFinite, delta != 0 else {
                return false
            }
            let sensitivity = event.hasPreciseScrollingDeltas ? 0.008 : 0.08
            let exponent = min(0.5, max(-0.5, delta * sensitivity))
            onScroll(exp(exponent), location)
            return true
        }
    }
}
#endif
