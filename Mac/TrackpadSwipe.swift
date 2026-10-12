import AppKit
import SwiftUI

/// Two-finger swipes on a trackpad, reported like a drag: the running sideways distance in the
/// direction the fingers move, then at the end where a flick would carry it. Vertical scrolling,
/// mice and swipes that start elsewhere pass straight through, and so do clicks.
struct TrackpadSwipe: NSViewRepresentable {
    var changed: (CGFloat) -> Void
    var ended: (_ projected: CGFloat) -> Void

    func makeNSView(context: Context) -> SwipeView { SwipeView() }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.changed = changed
        view.ended = ended
    }

    final class SwipeView: NSView {
        var changed: (CGFloat) -> Void = { _ in }
        var ended: (CGFloat) -> Void = { _ in }
        private var monitor: Any?
        private enum State { case idle, swiping, ignoring }
        private var state = State.idle
        private var translation: CGFloat = 0
        private var velocity: CGFloat = 0
        private var lastTime: TimeInterval = 0
        /// The glide after a swipe this view used, which it swallows too.
        private var swallowMomentum = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event) ? nil : event
            }
        }

        /// Whether the event was used.
        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window, event.hasPreciseScrollingDeltas else { return false }
            if !event.momentumPhase.isEmpty { return swallowMomentum }
            // Which way the fingers moved, whichever way scrolling is set.
            let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            let dy = event.scrollingDeltaY

            if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
                swallowMomentum = false
                guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
                    state = .ignoring
                    return false
                }
                state = .idle
                translation = 0
                velocity = 0
                lastTime = event.timestamp
                if event.phase.contains(.mayBegin) { return false }
            }
            if event.phase.contains(.began) || event.phase.contains(.changed) {
                if state == .idle, dx != 0 || dy != 0 {
                    state = abs(dx) > abs(dy) ? .swiping : .ignoring
                }
                guard state == .swiping else { return false }
                translation += dx
                let dt = max(event.timestamp - lastTime, 1.0 / 240)
                velocity = velocity * 0.5 + dx / dt * 0.5   // points a second, smoothed
                lastTime = event.timestamp
                changed(translation)
                return true
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                let wasSwiping = state == .swiping
                state = .idle
                guard wasSwiping else { return false }
                swallowMomentum = true
                // A stale velocity means the fingers stopped before lifting.
                let still = event.timestamp - lastTime > 0.08
                ended(translation + (still ? 0 : velocity * 0.4))
                return true
            }
            return false
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
