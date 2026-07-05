//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit

/// A transparent AppKit layer that turns trackpad/mouse scrolling over the canvas into panning,
/// without converting the canvas to a `ScrollView` (which would fight the card drag gestures and
/// the manual `.scaleEffect` zoom).
///
/// It uses a local `NSEvent` monitor scoped to the view's bounds so it reliably sees scroll events
/// regardless of the SwiftUI responder chain, and it never intercepts mouse clicks (`hitTest`
/// returns `nil`) so cards stay interactive. Pinch-to-zoom is handled separately by the view's
/// `MagnificationGesture`.
struct TrackpadScrollCatcher: NSViewRepresentable {

    /// Scroll delta in points.
    var onScroll: (CGSize) -> Void

    func makeNSView(context: Context) -> ScrollCatchingView {
        let view = ScrollCatchingView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollCatchingView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: ScrollCatchingView, coordinator: ()) {
        nsView.teardownMonitor()
    }

    final class ScrollCatchingView: NSView {
        var onScroll: ((CGSize) -> Void)?
        // Touched only on the main thread; `nonisolated(unsafe)` lets `teardownMonitor()` run from
        // the nonisolated `deinit` without an actor hop.
        nonisolated(unsafe) private var monitor: Any?

        // Don't steal mouse clicks — panning is handled via the scroll-event monitor.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                teardownMonitor()
            } else if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                    self?.handle(event) ?? event
                }
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            let pointInView = convert(event.locationInWindow, from: nil)
            guard bounds.contains(pointInView) else { return event }

            var dx = event.scrollingDeltaX
            var dy = event.scrollingDeltaY
            if !event.hasPreciseScrollingDeltas {
                dx *= 10
                dy *= 10
            }
            onScroll?(CGSize(width: dx, height: dy))
            return nil // consume so nothing else scrolls
        }

        // `nonisolated` so it's callable from the (nonisolated) `deinit` under the module's
        // main-actor-by-default isolation. Monitor access happens on the main thread in practice.
        nonisolated func teardownMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit { teardownMonitor() }
    }
}
