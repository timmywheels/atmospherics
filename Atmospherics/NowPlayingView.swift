import SwiftUI

#if os(iOS)
/// Home screen: a breathing halo of the current sounds, the mix name, and the main controls.
/// (The Mac's window, `MacListen`, is built from the same parts below.)
struct NowPlayingView: View {
    @Environment(Mixer.self) private var mixer
    @State private var showLibrary = false
    @State private var dragX: CGFloat = 0
    @State private var showMixer = false
    /// How far up Layers is pulled.
    @State private var layersDetent = MixerView.opening
    /// The whole screen's height, for where Layers comes up to.
    @State private var screenHeight: CGFloat = 0
    /// The Library opened to search (from the name or Where to?): ready to type.
    @State private var searchFirst = false
    @State private var hint: String?
    /// How many of the one-time hints have been shown.
    @AppStorage("hintStep") private var hintStep = 0

    private static let hints = [
        "Swipe left or right to travel",
        "Tap the light to see its layers",
        "Swipe up for your library",
        "Hold play for a sleep timer",
        "Tap the name to search",
        "Hold the light, then drag to move it",
    ]

    /// Shows each hint once, a few seconds apart, the first times you open the app.
    private func runHints() async {
        while hintStep < Self.hints.count {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.5)) { hint = Self.hints[hintStep] }
            hintStep += 1
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.smooth(duration: 0.5)) { hint = nil }
        }
    }

    /// The Library, ready to type where to.
    private func openSearch() {
        searchFirst = true
        showLibrary = true
    }

    /// Layers, coming up halfway so the form stays in view above it.
    private func openLayers() {
        layersDetent = MixerView.opening
        showMixer = true
    }

    /// Tapping the form: Layers, or with Layers up, puts it away.
    private func toggleLayers() {
        if showMixer { showMixer = false } else { openLayers() }
    }

    /// Where the top of Layers is on the screen while it's up (halfway, the system's `.medium`;
    /// it's the same once it's pulled higher, with nothing to see), so the form can rise into the
    /// room above it.
    private var layersTop: CGFloat? {
        guard showMixer, MixerView.detents.contains(.medium), screenHeight > 0 else { return nil }
        return screenHeight / 2
    }

    /// A scene in the next of its skies.
    private func otherSkies() {
        if inAtmosphere { mixer.cycleAtmosphereSky() }
    }

    /// Playing an atmosphere (not a Library mix started from one): its own weather and time apply.
    private var inAtmosphere: Bool { mixer.mode == .atmosphere && mixer.activePreset == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // What swiping goes through: Outside, Scenes, Focus, Relax, Sleep, Meditate, round and round.
            ModeWheel()
                .padding(.horizontal, -28)

            Carousel(dragX: $dragX, openMixer: toggleLayers, search: openSearch, drawerTop: layersTop)
                .animation(.smooth(duration: 0.5), value: layersTop)
                .frame(minHeight: 400, maxHeight: .infinity)

            .haptic(.tap, trigger: mixer.mode)

            VStack(alignment: .leading, spacing: 0) {
                // What's playing (tap it for its layers), a way back if you've tuned it, and the
                // sleep timer if there is one.
                HStack(spacing: 14) {
                    Button { openLayers() } label: {
                        LayerStrip(orbs: mixer.byVolume)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Layers")
                    // The sleep timer, when it's other than the usual 8 hours.
                    if mixer.timer != .off && mixer.timer != .eightHours {
                        Text(mixer.timer.label)
                            .font(Theme.label(11))
                            .foregroundStyle(Theme.muted)
                            .transition(.opacity)
                    }
                    ResetTuning()
                }
                .padding(.top, 14)
                .animation(.smooth, value: mixer.timer)
                .animation(.smooth, value: mixer.currentPlaceIsTweaked)

                VolumeLine()
                    .frame(height: 40)
                    .padding(.top, 2)

                // Where to go next, and play, in reach of a thumb.
                HStack(spacing: 12) {
                    WhereToBar(search: openSearch)
                    PlayButton()
                }
                .padding(.top, 10)
            }
            // Under Layers, gone, so its glass is clear.
            .opacity(showMixer ? 0 : 1)
            .animation(.smooth(duration: 0.3), value: showMixer)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background {
            SceneWash(orbs: mixer.byVolume)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { g in
                let up = -g.translation.height
                // A drag on the glass turned it; it wasn't a swipe.
                guard abs(up) > 80, abs(up) > abs(g.translation.width) * 1.5,
                      !SculptureSpin.home.recentlyTouched else { return }
                if showMixer {
                    // Above Layers: up pulls it the rest of the way, down puts it away.
                    if up > 0 { layersDetent = .large } else { showMixer = false }
                } else if up > 0 {
                    showLibrary = true
                }
                // Down does nothing: it came too easily by accident.
            }
        )
        .accessibilityAction(named: "Library") { showLibrary = true }
        .accessibilityAction(named: "Search") { openSearch() }
        .accessibilityAction(named: "Other vibes", otherSkies)
        .accessibilityAction(named: "Layers") { openLayers() }
        .sheet(isPresented: $showMixer) {
            MixerView(detent: $layersDetent)
        }
        .overlay(alignment: .bottom) {
            ZStack {
                if let text = mixer.notice ?? hint { HintBubble(text: text) }
            }
            .padding(.bottom, 130)
            .animation(.smooth(duration: 0.3), value: mixer.notice)
        }
        .task { await runHints() }
        // A new mix from scratch: Tune, all the way up, once the Library has gone.
        .onChange(of: mixer.tuneRequests) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(550))
                layersDetent = .large
                showMixer = true
            }
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(current: mixer.activePreset, focus: searchFirst)
                .onDisappear { searchFirst = false }
        }
        .haptic(.thud, trigger: mixer.shuffleCount)
        .haptic(.tap, trigger: mixer.atmosphere?.sky)
        // A tap as Layers or the Library opens, however it was asked for.
        .haptic(.tap, trigger: showMixer) { _, now in now }
        .haptic(.tap, trigger: showLibrary) { _, now in now }
    }

}
#endif

/// The halo, title, weather and layers of where you are. Swipe across to go on or back: the form
/// stays where it is and turns into the next place under the finger (sounds the two share grow or
/// shrink, the rest fade out or in), while the names cross-fade, drifting the way you swipe. Let go
/// past a third of the way, or flick, and it goes there; otherwise it eases back. On a Mac, two
/// fingers on the trackpad do the same, and the keyboard and menus morph it too. A drag that starts
/// on the glass turns the form instead. With Layers up from the bottom, the form rises into the
/// room above it, and the names and buttons, under it, fade away.
struct Carousel: View {
    @Environment(Mixer.self) private var mixer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the finger has gone: only a nudge of the names where there's nowhere to go.
    @Binding var dragX: CGFloat
    let openMixer: () -> Void
    /// Tapping the name: search.
    let search: () -> Void
    /// Where on the screen the top of a drawer over the place is, while there's one up.
    var drawerTop: CGFloat? = nil
    @State private var pastThreshold = false
    /// How far the form has turned under the finger, in notches of about 15°: a soft tick each.
    @State private var turnNotch = 0
    /// Two places being blended, while a swipe or a trip is under way, and how far (`blend`, 0 to 1).
    @State private var pair: Pair?
    @State private var blend: Double = 0
    /// Finishing a trip, or easing back from one called off.
    @State private var landing = false
    /// The form, whose glass a drag can take hold of.
    @State private var formSize: CGSize = .zero
    /// Where the current drag started, and whether that was on the glass.
    @State private var grab: (at: CGPoint, onForm: Bool)?
    /// The form, picked up by holding it: a drag then moves and turns it instead of traveling.
    /// (On a Mac, where traveling is two fingers on the trackpad, a drag on it always does.)
    @State private var held = false
    /// How far the held form has been pulled from its place; it springs back when let go.
    @State private var lift: CGSize = .zero
    /// The form was carried, so letting go of it isn't a tap. (A hold let go without moving is.)
    @State private var skipTap = false

    private struct Pair {
        let from: Mixer.Page
        let to: Mixer.Page
        let forward: Bool
    }

    private var livePage: Mixer.Page {
        Mixer.Page(title: mixer.title, line: mixer.weather.line, orbs: mixer.byVolume, lines: mixer.titleLines)
    }

    /// Tapping the form: Layers.
    private func tapForm() {
        if skipTap { skipTap = false; return }
        openMixer()
    }

    /// Holding the form picks it up, with a tap you can feel and the form rising a little.
    private var hold: some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard !held, !landing, pair == nil, case .second(true, let drag?) = value,
                      SoundForm.touches(drag.startLocation, orbs: mixer.byVolume, size: formSize) else { return }
                withAnimation(.spring(duration: 0.25, bounce: 0.3)) { held = true }
                Haptics.play(.tap)
            }
            .onEnded { _ in letGo() }
    }

    private func letGo() {
        guard held else { return }
        withAnimation(.spring(duration: 0.5, bounce: 0.35)) {
            held = false
            lift = .zero
        }
        // Lets a tap that never came through stop waiting.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            skipTap = false
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let live = livePage
            // The room above a drawer, for the form alone.
            let room = drawerTop.map { max(160, $0 - proxy.frame(in: .global).minY - 10) }
            MorphView(from: pair?.from ?? live, to: pair?.to ?? live, forward: pair?.forward ?? true, t: pair == nil ? 0 : blend,
                      still: pair == nil, nudge: pair == nil ? dragX * 0.4 : 0, room: room, favorite: mixer.favoriteKey,
                      lift: lift, held: held,
                      formSize: $formSize, openMixer: tapForm, search: search)
                .frame(width: w, height: proxy.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(drag(width: w))
                #if os(iOS)
                .simultaneousGesture(hold)
                #endif
                #if os(macOS)
                .background(TrackpadSwipe(changed: { follow($0, width: w) },
                                          ended: { release(projected: $0, width: w) }))
                #endif
                .onChange(of: mixer.travelRequest) { _, request in
                    guard let request, !landing else { return }
                    arrive(forward: request.forward, duration: 0.55)
                }
        }
        .onAppear { mixer.carouselShowing = true }
        .onDisappear { mixer.carouselShowing = false }
        .haptic(.tick, trigger: pastThreshold) { _, now in now }
        .accessibilityAction(named: "Travel somewhere new") { mixer.travel(forward: true) }
        .accessibilityAction(named: "Go back") { mixer.travel(forward: false) }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { g in
                if turnsForm(g) {
                    SculptureSpin.home.drag(g.translation)
                    // Held, it comes with the finger a way, pulling harder the further it goes.
                    if held {
                        skipTap = true
                        lift = CGSize(width: 70 * tanh(g.translation.width / 180), height: 70 * tanh(g.translation.height / 180))
                    }
                    let notch = Int((abs(g.translation.width) + abs(g.translation.height)) / 26)
                    if notch != turnNotch {
                        turnNotch = notch
                        Haptics.play(.soft)
                    }
                    return
                }
                guard abs(g.translation.width) > abs(g.translation.height) else { return }
                follow(g.translation.width, width: width)
            }
            .onEnded { g in
                if turnsForm(g) {
                    turnNotch = 0
                    letGo()
                    return SculptureSpin.home.release(g.velocity, coast: !reduceMotion)
                }
                release(projected: g.predictedEndTranslation.width, width: width)
            }
    }

    /// Whether this drag took hold of the glass: decided where it starts, and kept for the drag.
    private func turnsForm(_ g: DragGesture.Value) -> Bool {
        if let grab, grab.at == g.startLocation { return grab.onForm }
        #if os(iOS)
        let onForm = held
        #else
        let onForm = !landing && pair == nil && SoundForm.touches(g.startLocation, orbs: mixer.byVolume, size: formSize)
        #endif
        grab = (g.startLocation, onForm)
        return onForm
    }

    /// The form turns toward where the finger is heading, all the way at most of the width across.
    /// The place it's turning into is worked out once, as the swipe sets off that way.
    private func follow(_ translation: CGFloat, width: CGFloat) {
        guard !landing else { return }
        let forward = translation < 0
        guard let destination = forward ? mixer.next : mixer.previous else {
            // Nowhere that way: the names give a little, and come back.
            pair = nil
            dragX = 40 * tanh(translation / 120)
            return
        }
        dragX = translation
        if pair?.forward != forward {
            pair = Pair(from: livePage, to: mixer.page(for: destination), forward: forward)
        }
        blend = min(1, Double(abs(translation) / (width * 0.7)))
        pastThreshold = blend > 0.33
    }

    /// Let go: `projected` is where a flick would carry the finger.
    private func release(projected: CGFloat, width: CGFloat) {
        guard !landing else { return }
        pastThreshold = false
        guard let pair else {
            withAnimation(.spring(duration: 0.35, bounce: 0.25)) { dragX = 0 }
            return
        }
        dragX = 0
        // Go only if it's past a third of the way, or flicked onward; pulling back calls it off.
        let commit = (projected < 0) == pair.forward && (blend > 0.33 || abs(projected) > width * 0.5)
        if commit {
            arrive(forward: pair.forward, duration: 0.35)
        } else {
            landing = true
            withAnimation(.spring(duration: 0.35, bounce: 0)) { blend = 0 } completion: {
                self.pair = nil
                landing = false
            }
        }
    }

    /// Goes on or back: the sound switches at once (it glides over by itself) while the form and
    /// the names finish turning into the place arrived at.
    private func arrive(forward: Bool, duration: Double) {
        guard let destination = forward ? mixer.next : mixer.previous else { return }
        if pair?.forward != forward {
            pair = Pair(from: livePage, to: mixer.page(for: destination), forward: forward)
            blend = 0
        }
        landing = true
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { mixer.travel(forward: forward) }
        withAnimation(.easeOut(duration: duration)) { blend = 1 } completion: {
            // Arrived: the place turned into is the live one now, drawn the same.
            withTransaction(quiet) {
                pair = nil
                blend = 0
            }
            landing = false
        }
    }
}

/// One place turning into another, `t` of the way from `from` to `to`: the form with each sound
/// at its level that far between them (sounds only one of them has fade out or in), and the names
/// cross-fading, drifting the way it goes. Still (`from` and `to` both where you are), the name
/// opens search. Given `room` (with a drawer up below), the form fits
/// in that much at the top, and the names, under the drawer, fade away.
private struct MorphView: View, Animatable {
    let from: Mixer.Page
    let to: Mixer.Page
    let forward: Bool
    var t: Double
    let still: Bool
    let nudge: CGFloat
    let room: CGFloat?
    let favorite: String?
    /// Held: picked up, a little bigger, pulled `lift` from its place.
    var lift: CGSize = .zero
    var held = false
    @Binding var formSize: CGSize
    let openMixer: () -> Void
    let search: () -> Void

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SoundForm(orbs: Self.blend(from.orbs, to.orbs, t))
                .frame(height: room)
                .frame(maxHeight: room == nil ? .infinity : nil)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { formSize = $0 }
                .scaleEffect(held ? 1.06 : 1)
                .offset(lift)
                .contentShape(Rectangle())
                .onTapGesture { openMixer() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(room == nil ? "Open layers" : "Close layers")
            #if os(iOS)
            // The names, with the bookmark that saves what's playing up by the name.
            HStack(alignment: .top, spacing: 8) {
                crossfade
                Spacer(minLength: 0)
                bookmark(size: 21)
                    .padding(.top, 14)
            }
            .opacity(room == nil ? 1 : 0)
            .allowsHitTesting(room == nil)
            .accessibilityHidden(room != nil)
            #else
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                crossfade
                bookmark(size: 19)
                    .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] + 7 }
                Spacer(minLength: 0)
            }
            #endif
        }
    }

    /// The bookmark, keeping its place whether or not it shows (mid-swipe, or for where you are),
    /// so the names never shift as one place turns into the next.
    private func bookmark(size: CGFloat) -> some View {
        ZStack {
            Color.clear.frame(width: 40, height: 40)
            if let favorite { FavoriteToggle(key: favorite, size: size) }
        }
        .opacity(still && favorite != nil ? 1 : 0)
        .allowsHitTesting(still && favorite != nil)
        .animation(.smooth(duration: 0.2), value: still)
    }

    /// The names going and coming, each drifting a little the way it goes.
    private var crossfade: some View {
        let drift: CGFloat = 36 * (forward ? -1 : 1)
        return ZStack(alignment: .bottomLeading) {
            names(from, live: still)
                .opacity(1 - t)
                .offset(x: drift * t + nudge)
            names(to, live: false)
                .opacity(t)
                .offset(x: -drift * (1 - t))
                .accessibilityHidden(true)
        }
    }

    private func names(_ page: Mixer.Page, live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { search() } label: {
                PageTitle(lines: page.lines ?? [page.title], chevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Search the Library")
            PageLines(line: page.line)
        }
        .allowsHitTesting(live)
    }

    /// The sounds `t` of the way from one mix to another: each at its level that far between them,
    /// turned toward where it sits in the second, loudest first. A sound keeps the same identity
    /// throughout, so its light grows and shrinks rather than going out and coming back.
    static func blend(_ a: [Orb], _ b: [Orb], _ t: Double) -> [Orb] {
        func angle(_ o: Orb) -> Double { atan2(o.y - 0.5, o.x - 0.5) }
        var first: [SoundKind: Orb] = [:], second: [SoundKind: Orb] = [:]
        for o in a where first[o.kind] == nil || o.volume > first[o.kind]!.volume { first[o.kind] = o }
        for o in b where second[o.kind] == nil || o.volume > second[o.kind]!.volume { second[o.kind] = o }
        var kinds = b.map(\.kind)
        for o in a where second[o.kind] == nil { kinds.append(o.kind) }
        var seen = Set<SoundKind>()
        return kinds.filter { seen.insert($0).inserted }.compactMap { kind -> Orb? in
            let oa = first[kind], ob = second[kind]
            let va = oa?.volume ?? 0, vb = ob?.volume ?? 0
            let v = va + (vb - va) * t
            guard v > 0.004 else { return nil }
            let from = (oa ?? ob).map(angle) ?? 0
            let to = ob.map(angle) ?? from
            var turn = to - from
            if turn > .pi { turn -= 2 * .pi } else if turn < -.pi { turn += 2 * .pi }
            let at = from + turn * t, r = (1 - v) * 0.5
            return Orb(id: kind.stableID, kind: kind, x: 0.5 + cos(at) * r, y: 0.5 + sin(at) * r)
        }
        .sorted { $0.volume > $1.volume }
    }
}

/// The page's name, large: an atmosphere's over two lines ("A log cabin / in a snowstorm"),
/// with a chevron after the last line to say it opens search (kept, hidden, on neighbouring
/// pages so their titles sit the same).
private struct PageTitle: View {
    let lines: [String]
    var chevron = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(line)
                        .font(Theme.display(lines.count > 1 ? 46 : 52))
                        .tracking(-0.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if i == lines.count - 1 {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .opacity(chevron ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PageLines: View {
    let line: String
    var body: some View {
        Text(line)
            .font(Theme.body(15))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 10)
    }
}

/// The sounds playing, loudest first, each with a dot in its light's color. Always one line:
/// as many as fit, then "+2" for the rest, so it never wraps.
struct LayerStrip: View {
    let orbs: [Orb]
    var color: Color = Theme.muted

    private var kinds: [SoundKind] {
        var seen = Set<SoundKind>()
        return orbs.sorted { $0.volume > $1.volume }
            .filter { $0.volume >= 0.05 && seen.insert($0.kind).inserted }
            .map(\.kind)
    }

    var body: some View {
        let kinds = kinds
        ViewThatFits(in: .horizontal) {
            ForEach(Array((1...max(1, kinds.count)).reversed()), id: \.self) { n in
                row(Array(kinds.prefix(n)), more: kinds.count - n)
            }
        }
        .font(Theme.label(11))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kinds.map(\.name).joined(separator: ", "))
    }

    private func row(_ shown: [SoundKind], more: Int) -> some View {
        HStack(spacing: 14) {
            ForEach(shown, id: \.self) { kind in
                HStack(spacing: 6) {
                    Circle().fill(kind.orb).frame(width: 5, height: 5)
                    Text(kind.short)
                }
            }
            if more > 0 { Text("+\(more)") }
        }
        .fixedSize()
    }
}

/// What's playing, as a form: the sculpture of its sounds, turning slowly in a soft bloom of their
/// colors (the halo behind it).
struct SoundForm: View {
    let orbs: [Orb]
    var live = true

    /// How it's seen: a little from above, filling most of the width.
    static let pitch = 0.5, extent = 0.8

    var body: some View {
        ZStack {
            Halo(orbs: orbs)
                .opacity(0.4)
            SculptureView(orbs: orbs, style: .home, pitch: Self.pitch, extent: Self.extent, animated: live)
        }
    }

    /// Whether a point in a form of this size is on the glass, as it's turned right now.
    static func touches(_ point: CGPoint, orbs: [Orb], size: CGSize) -> Bool {
        let spin = SculptureSpin.home
        let camera = SculptureCamera(yaw: spin.yaw, pitch: pitch + spin.tilt, size: size, extent: extent)
        return SculptureStyle.home.touches(point, orbs: orbs, camera: camera)
    }
}

/// Soft blurred lights, one per sound. Louder sounds are bigger and sit nearer the center.
/// Each light wanders slowly on its own path, and the whole halo drifts, so it feels alive.
struct Halo: View {
    let orbs: [Orb]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash: Double = 0
    @State private var seenStrikes: Int32 = 0

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                // Whole-halo drift: a slow figure-eight a few points across.
                let drift = CGPoint(x: sin(t * 0.07) * 12, y: sin(t * 0.11) * 8)
                ZStack {
                    ForEach(Array(orbs.enumerated()), id: \.element.id) { i, orb in
                        // A fixed spot per sound, so lights grow and shrink instead of swapping places.
                        let slot = Double(SoundKind.allCases.firstIndex(of: orb.kind) ?? i)
                        let angle = slot * 2.399 + 0.4
                        let distance = (1 - orb.volume) * 70
                        // Slightly smaller and softer than the CSS values: SwiftUI's blur
                        // spreads less, so the same numbers render bigger and harsher.
                        let size = (90 + orb.volume * 200) * 0.85
                        let phase = slot * 1.9
                        let wander = CGPoint(x: sin(t * 0.13 + phase) * 16, y: cos(t * 0.1 + phase * 1.3) * 14)
                        Breathing(period: 7 + Double(i) * 1.7) {
                            Circle()
                                .fill(orb.kind.halo.opacity(0.85))
                                .frame(width: size, height: size)
                                .blur(radius: 22)
                        }
                        // Fade with volume, so arriving and leaving sounds melt in and out.
                        .opacity(min(1, orb.volume * 3))
                        .blendMode(.screen)
                        .position(x: center.x + cos(angle) * distance + wander.x + drift.x,
                                  y: center.y + sin(angle) * distance + wander.y + drift.y)
                    }
                }
                .compositingGroup()
                .overlay {
                    // A lightning strike lights the halo for a moment.
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.55 * flash), .clear],
                                             center: .center, startRadius: 0, endRadius: proxy.size.width * 0.55))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
                .onChange(of: timeline.date) { _, _ in
                    let strikes = LightningFlash.strikes.pointee
                    if strikes != seenStrikes {
                        seenStrikes = strikes
                        if hasLightning { flash = 1 }
                    } else if flash > 0 {
                        flash = max(0, flash - 0.08)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var hasLightning: Bool { orbs.contains { $0.kind == .lightning && $0.volume > 0.05 } }
}

/// Slowly scales its content between 1 and 1.08, like the design's `breathe` keyframes.
private struct Breathing<Content: View>: View {
    let period: Double
    @ViewBuilder let content: Content
    @State private var expanded = false

    var body: some View {
        content
            .scaleEffect(expanded ? 1.08 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) {
                    expanded = true
                }
            }
    }
}

/// A small outlined button beside what's playing.
private struct SoundsPill: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.label(12, .medium))
                .foregroundStyle(Theme.text)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// When you've tuned the scene playing (in Layers): a plain way back to how it sounds by default,
/// after asking.
struct ResetTuning: View {
    @Environment(Mixer.self) private var mixer
    @State private var confirming = false

    var body: some View {
        if mixer.currentPlaceIsTweaked {
            SoundsPill(title: "Reset", symbol: "arrow.counterclockwise") { confirming = true }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .accessibilityLabel("Reset this scene")
                .accessibilityHint("Back to how it sounds by default")
                #if os(macOS)
                .help("Put this scene back to how it sounds by default")
                #endif
                .confirmReset(isPresented: $confirming)
        }
    }
}

extension View {
    /// Asks before putting the scene back to how it sounds by default, since that loses your tuning.
    func confirmReset(isPresented: Binding<Bool>) -> some View {
        modifier(ConfirmReset(isPresented: isPresented))
    }
}

private struct ConfirmReset: ViewModifier {
    @Environment(Mixer.self) private var mixer
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog("Reset this scene?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                Haptics.play(.tap)
                withAnimation(.smooth) { mixer.resetCurrentPlace() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your changes to its sounds will be lost.")
        }
    }
}

/// Where to? The Library, ready to type: anything in it, or somewhere new in your own words.
private struct WhereToBar: View {
    let search: () -> Void

    var body: some View {
        Button(action: search) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                Text("Where to?")
                    .font(Theme.label(15))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondary)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityLabel("Search")
        .accessibilityHint("Say where you'd like to go")
    }
}

private struct PlayButton: View {
    @Environment(Mixer.self) private var mixer
    @State private var choosingTimer = false
    @State private var held = 0

    var body: some View {
        // A quiet ring rather than a big disc, so the scene stays the focus.
        ZStack {
            Circle().strokeBorder(Theme.text.opacity(0.8), lineWidth: 1.5)
            if mixer.isPlaying {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5).frame(width: 4, height: 17)
                    RoundedRectangle(cornerRadius: 1.5).frame(width: 4, height: 17)
                }
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 18))
                    .offset(x: 1.5)
            }
        }
        .foregroundStyle(Theme.text)
        .frame(width: 56, height: 56)
        .contentShape(Circle())
        // Tap to play or pause; hold for a sleep timer.
        .onTapGesture { mixer.togglePlayback() }
        .onLongPressGesture(minimumDuration: 0.45) {
            held += 1
            choosingTimer = true
        }
        .confirmationDialog("Sleep timer", isPresented: $choosingTimer, titleVisibility: .visible) {
            ForEach(Mixer.Timer.allCases, id: \.self) { t in
                Button(t == .off ? "No timer" : "Stop after \(t.label)" + (t == mixer.timer ? "  ✓" : "")) {
                    mixer.setTimer(t)
                }
            }
        }
        .haptic(.thud, trigger: mixer.isPlaying)
        .haptic(.thud, trigger: held)
        .haptic(.tick, trigger: mixer.timer)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(mixer.isPlaying ? "Pause" : "Play")
        .accessibilityHint("Hold for a sleep timer")
        .accessibilityAction { mixer.togglePlayback() }
        .accessibilityAction(named: "Sleep timer") { choosingTimer = true }
    }
}

/// A slim, calm wave under the readout. Its height follows how loud the mix is (smoothed over
/// about half a second) and it drifts slowly sideways, so it feels alive without twitching.
/// How loud Atmospherics plays, apart from the system volume, so a soundscape can sit low while
/// notifications stay loud: the sound's line runs as far across as the volume, with a dot where it
/// ends and a faint line after. Tap or drag along it to set the volume, or tap the speaker to mute
/// it and back.
struct VolumeLine: View {
    @Environment(Mixer.self) private var mixer
    @State private var sliding = false
    /// Where to come back to after muting.
    @State private var unmuted = 0.7

    private var symbol: String {
        switch mixer.volume {
        case ..<0.01: "speaker.slash"
        case ..<0.34: "speaker.wave.1"
        case ..<0.67: "speaker.wave.2"
        default: "speaker.wave.3"
        }
    }

    private func toggleMute() {
        withAnimation(.snappy(duration: 0.25)) {
            if mixer.volume > 0.01 {
                unmuted = mixer.volume
                mixer.volume = 0
            } else {
                mixer.volume = max(0.1, unmuted)
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleMute) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 26, alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = width * CGFloat(mixer.volume)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.text.opacity(0.12)).frame(height: 1)
                    Waveform().frame(width: max(1, x))
                    Circle()
                        .fill(Theme.text)
                        .frame(width: sliding ? 12 : 9, height: sliding ? 12 : 9)
                        .shadow(color: .black.opacity(0.35), radius: 3)
                        .offset(x: x - (sliding ? 6 : 4.5))
                }
                .frame(width: width, height: proxy.size.height, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            sliding = true
                            mixer.volume = min(1, max(0, Double(g.location.x / max(1, width))))
                        }
                        .onEnded { _ in sliding = false }
                )
            }
        }
        .animation(.snappy(duration: 0.15), value: sliding)
        // A tick per 10% as it slides.
        .haptic(.tick, trigger: Int((mixer.volume * 10).rounded(.down))) { _, _ in sliding }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue(mixer.volume < 0.01 ? "Muted" : "\(Int((mixer.volume * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            mixer.volume = min(1, max(0, mixer.volume + (direction == .increment ? 0.1 : -0.1)))
        }
        .accessibilityAction(named: mixer.volume < 0.01 ? "Unmute" : "Mute", toggleMute)
    }
}

struct Waveform: View {
    @Environment(Mixer.self) private var mixer
    @State private var level: Double = 0

    var body: some View {
        // Keep animating after pause until the wave has settled flat.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !mixer.isPlaying && level < 0.001)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
            Canvas { ctx, size in
                let mid = size.height / 2
                let amplitude = mid * 0.45 * min(1, level * 7)
                var path = Path()
                let samples = 90
                for i in 0...samples {
                    let x = Double(i) / Double(samples)
                    let edge = sin(x * .pi)   // taper into the edges
                    // Two slow waves at different speeds give a soft, organic shape.
                    let y = 0.65 * sin(x * 2 * .pi * 2.2 - t * 1.8) + 0.35 * sin(x * 2 * .pi * 3.7 + t * 1.2)
                    let p = CGPoint(x: x * size.width, y: mid - y * amplitude * edge)
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                let colors = mixer.byVolume.prefix(3).map(\.kind.orb)
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: colors.isEmpty ? [Theme.muted] : colors + [colors[0]]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                ctx.opacity = mixer.isPlaying ? 0.85 : 0.25
                ctx.drawLayer { glow in
                    glow.addFilter(.blur(radius: 5))
                    glow.stroke(path, with: shading, lineWidth: 3)
                }
                ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
            .onChange(of: timeline.date) { _, _ in
                let peaks = mixer.isPlaying ? mixer.scope.snapshot() : []
                let rms = peaks.isEmpty ? 0 : sqrt(peaks.map { Double($0 * $0) }.reduce(0, +) / Double(peaks.count))
                level += (rms - level) * 0.03   // slow, so loudness changes never jolt the height
            }
        }
        .accessibilityHidden(true)
    }
}
