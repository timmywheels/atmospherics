import SwiftUI

/// Tune on the Mac: a drawer over the right of Listen, as on the phone, scrolling as one piece:
/// what's playing and its weather or other skies, every layer with its level, then every sound to
/// add or take away, their pills wrapping. Drag its left edge to make it wider or narrower (it's
/// kept); ⌘E, Esc or × puts it away.
struct MacLayers: View {
    @Environment(MacNavigation.self) private var navigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TuneHeader(reset: { navigation.resetting = true }, save: { navigation.saving = true },
                           close: { navigation.tuning = false })
                    .padding(.top, 18)
                SoundList(embedded: true)
                SoundSections(embedded: true)
                    .padding(.bottom, 12)
            }
        }
        .scrollIndicators(.automatic)
    }
}

/// The drawer Tune sits in: its own glass over the scene, a shadow to the left, and a left edge to
/// drag.
struct TuneDrawer: View {
    @Environment(MacNavigation.self) private var navigation
    @AppStorage("tuneWidth") private var width: Double = 380
    @State private var dragFrom: Double?
    @State private var hoveringEdge = false
    let room: CGFloat

    private var shown: CGFloat { CGFloat(min(max(width, 320), Double(max(320, room * 0.8)))) }

    var body: some View {
        MacLayers()
            .frame(width: shown)
            .frame(maxHeight: .infinity)
            // Below the toolbar, not under it: the tabs stay over Listen's own top.
            .background(.ultraThinMaterial, ignoresSafeAreaEdges: [])
            .background(Theme.background.opacity(0.55), ignoresSafeAreaEdges: [])
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.hairline).frame(width: 1)
            }
            .overlay(alignment: .leading) { edge }
            .shadow(color: .black.opacity(0.35), radius: 24, x: -6)
            .onExitCommand { navigation.tuning = false }
    }

    /// The left edge, to drag: wider to the left, narrower to the right.
    private var edge: some View {
        Color.clear
            .frame(width: 10)
            .contentShape(Rectangle())
            .offset(x: -5)
            .onHover { inside in
                if inside, !hoveringEdge { NSCursor.resizeLeftRight.push() }
                if !inside, hoveringEdge { NSCursor.pop() }
                hoveringEdge = inside
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in
                    let start = dragFrom ?? Double(shown)
                    dragFrom = start
                    width = min(max(start - g.translation.width, 320), Double(max(320, room * 0.8)))
                }
                .onEnded { _ in dragFrom = nil })
            .accessibilityHidden(true)
    }
}
