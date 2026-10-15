import SwiftUI

#if os(iOS)
/// Layers, a drawer over the place: every sound that's playing, each with its own level to set
/// (`SoundList`). It comes up halfway, in glass, with the form still in view above it, so you can
/// watch it change as you set the levels (and turn it, or swipe on to the next place). Pulled up,
/// it fills the screen, washed in the colors of the mix, with every sound to add or take away below
/// (`SoundSections`). Swipe it down to put it away. (On the Mac, `MacLayers` shows the same parts.)
struct MixerView: View {
    @Environment(Mixer.self) private var mixer
    /// How far up it's pulled.
    @Binding var detent: PresentationDetent
    @State private var saving = false
    @State private var resetting = false
    /// How tall it is right now, following a finger pulling it up or down.
    @State private var height: CGFloat = 0
    /// How tall it is halfway up: the least it's been since it came up.
    @State private var halfway = CGFloat.infinity

    /// Halfway and all the way. (Before iOS 18 the layers fit rather than scroll, so only the whole
    /// screen has room for them.)
    static var detents: Set<PresentationDetent> { SoundList.scrolls ? [.medium, .large] : [.large] }
    /// Where it opens: halfway, where there's a halfway.
    static var opening: PresentationDetent { SoundList.scrolls ? .medium : .large }

    private var halves: Bool { Self.detents.contains(.medium) }
    /// How much more of it is showing than halfway.
    private var above: CGFloat { halfway.isFinite ? max(0, height - halfway) : 0 }

    var body: some View {
        Group {
            if SoundList.scrolls {
                // One piece that scrolls, as on the Mac: what it is, every layer at a fingertip's
                // height, then every sound to add, wrapping. Nothing squeezed into a box of its own.
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        SoundList(embedded: true)
                        SoundSections(embedded: true)
                            .padding(.bottom, 32)
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                // Before iOS 18 a drag across a layer holds a scroll view still: laid out for the
                // whole screen, the sounds to pick from below.
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        header
                        SoundList()
                    }
                    .frame(height: halves && halfway.isFinite ? halfway : nil)
                    if !halves || halfway.isFinite {
                        SoundSections(height: max(SoundSections.height, above))
                    }
                }
            }
        }
        // As tall as the drawer, not the sounds out of sight below.
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
            height = h
            if h > 100 { halfway = min(halfway, h) }
        }
        .foregroundStyle(Theme.text)
        // Glass while the place shows above it, the mix's colors as it comes up over the place.
        .background { SceneWash(orbs: mixer.orbs).opacity(halves ? min(1, above / SoundSections.height) : 1) }
        .presentationDetents(Self.detents, selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .modifier(DrawerFace())
        .saveMixPrompt(isPresented: $saving)
        .haptic(.tick, trigger: detent)
    }

    private var header: some View {
        TuneHeader(reset: { resetting = true }, save: { saving = true })
            .confirmReset(isPresented: $resetting)
            .padding(.top, 28)
    }
}

/// The drawer's face: the system's own Liquid Glass where there is it (iOS 26), frosted glass before.
private struct DrawerFace: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.presentationBackground(.ultraThinMaterial)
        }
    }
}
#endif

/// Every sound that's playing, a layer each in the order they came in, filled in its color as far
/// across as it's loud: tap or drag across one to set its level, or hold it to take it away. Last,
/// an empty layer brings in a sound that fits. They scroll when there are more than fit. (The
/// sounds to pick from are below, in `SoundSections`.)
struct SoundList: View {
    @Environment(Mixer.self) private var mixer
    /// Inside something that scrolls already (the Mac's Tune drawer): every layer, laid out whole.
    var embedded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mixer.currentPlaceIsTweaked ? "Your changes to \(mixer.currentPlaceName) are kept. Reset to hear it as it was."
                 : "Slide a layer to set it; pull it past silent to remove it.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 16)
            if embedded {
                rows(height: Self.fingertip)
            } else if Self.scrolls {
                // A fingertip's height and then some, however many are playing.
                ScrollView { rows(height: 72) }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                // Before iOS 18 a drag across a layer holds a list still, so they fit instead: as tall
                // as there's room for, down to a fingertip's height with a lot playing.
                GeometryReader { proxy in
                    rows(height: min(84, max(44, proxy.size.height / CGFloat(mixer.orbs.count + 1))))
                }
                .clipped()
            }
        }
        .animation(.snappy, value: mixer.orbs.map(\.id))
    }

    private func rows(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ForEach(mixer.orbs) { orb in
                LevelRow(orb: orb, height: height)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            AddLayer(height: height)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    /// A layer's height laid out whole: a fingertip and then some on the phone.
    static var fingertip: CGFloat {
        #if os(iOS)
        72
        #else
        64
        #endif
    }

    static var scrolls: Bool {
        #if os(iOS)
        if #available(iOS 18.0, *) { return true }
        return false
        #else
        return true
        #endif
    }
}

/// The top of Tune: what's playing, with the bookmark that saves it; for a real place its live
/// weather, for a scene its other skies (each another scene, to go to); and Reset, once it's
/// tuned, and Save as new.
struct TuneHeader: View {
    @Environment(Mixer.self) private var mixer
    let reset: () -> Void
    let save: () -> Void
    /// A way to put it away, where there's no other (the Mac's drawer).
    var close: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    // First, at the top left: where a Mac puts a way out.
                    if let close {
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(.white.opacity(0.06)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Close  ⌘E")
                        .accessibilityLabel("Close Tune")
                    }
                    Text("TUNE")
                        .font(Theme.caps(11))
                        .tracking(1.3)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                }
                // The name on a line of its own, so it's never cut short by the buttons.
                // In the serif, as on the home screen.
                HStack(alignment: .center, spacing: 6) {
                    Text(mixer.title)
                        .font(Theme.display(30))
                        .lineLimit(2)
                        .contentTransition(.opacity)
                    if let key = mixer.favoriteKey {
                        FavoriteToggle(key: key, size: 15)
                            .frame(width: 32, height: 32)
                    }
                }
            }
            if let live = mixer.liveLine {
                Text(live)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.secondary)
                    .contentTransition(.opacity)
            } else if mixer.mode == .atmosphere, mixer.activePreset == nil, let a = mixer.atmosphere {
                OtherSkies(scene: a)
            }
            HStack(spacing: 8) {
                if mixer.currentPlaceIsTweaked {
                    pill("Reset", action: reset)
                        .accessibilityLabel("Reset \(mixer.currentPlaceName) to default")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                pill("Save as new…", action: save)
                    .disabled(mixer.orbs.isEmpty)
                    .opacity(mixer.orbs.isEmpty ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
        .animation(.smooth, value: mixer.currentPlaceIsTweaked)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Text(title)
                .font(Theme.label(13, .medium))
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A scene's other vibes (its other skies), as places to go: "Snow · Rain · Clear", the one you're in lit. Each is
/// another scene, with its own tuning and its own bookmark.
private struct OtherSkies: View {
    @Environment(Mixer.self) private var mixer
    let scene: Atmosphere

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OTHER VIBES FOR THIS \(scene.setting.info.name.uppercased())")
                .font(Theme.caps(10))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            // Wrapping, so every one shows (a mouse can't scroll sideways).
            FlowLayout(spacing: 8) {
                ForEach(scene.setting.info.skies, id: \.self) { sky in
                    let here = sky == scene.sky
                    Button {
                        guard !here else { return }
                        Haptics.play(.thud)
                        withAnimation(.smooth) { mixer.setAtmosphereSky(sky) }
                    } label: {
                        Text(sky.name)
                            .font(Theme.body(13, .medium))
                            .foregroundStyle(here ? Theme.background : Theme.text)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 13)
                            .background(Capsule().fill(here ? Theme.text : .clear))
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(here ? .isSelected : [])
                }
            }
        }
    }
}

/// One sound as a layer: filled in its color from the left as far as it's loud, its name large and
/// its level small. Slide across it to move the level from where it is (a tap does nothing, so a
/// stray touch never changes it); keep pulling past silent and the layer comes away, to remove when
/// let go. A drag that starts up or down scrolls the list instead.
private struct LevelRow: View {
    @Environment(Mixer.self) private var mixer
    let orb: Orb
    let height: CGFloat
    /// The level the slide started from: a drag moves it from there, by how far the finger goes,
    /// so where the finger lands doesn't matter, and a tap does nothing.
    @State private var from: Double?
    /// How far the layer is pulled past silent, to the left: far enough and letting go removes it.
    @State private var pull: CGFloat = 0
    @State private var removing = false
    private static let removeAt: CGFloat = 80

    private var sliding: Bool { from != nil }

    private var percent: Int { Int((orb.volume * 100).rounded()) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let row = bar(width: width)
                .offset(x: -pull)
                .contentShape(Rectangle())
            #if os(iOS)
            if #available(iOS 18.0, *) {
                row.gesture(SidewaysPan { dx in slide(by: dx, of: width) } ended: { done in endSlide(done) })
            } else {
                row.gesture(DragGesture(minimumDistance: 6)
                    .onChanged { g in slide(by: g.translation.width, of: width) }
                    .onEnded { _ in endSlide(true) })
            }
            #else
            row.gesture(DragGesture(minimumDistance: 4)
                .onChanged { g in slide(by: g.translation.width, of: width) }
                .onEnded { _ in endSlide(true) })
            #endif
        }
        .frame(height: height)
        .contextMenu {
            Button(role: .destructive) {
                Haptics.play(.thud)
                withAnimation(.snappy) { mixer.remove(orb.id) }
            } label: { Label("Remove \(orb.kind.name)", systemImage: "xmark") }
        }
        // A tick per 10% as it slides, and a landing once it's pulled far enough to remove.
        .haptic(.thud, trigger: removing) { _, now in now }
        .haptic(.tick, trigger: percent / 10) { _, _ in sliding }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(orb.kind.name)
        .accessibilityValue(orb.kind.rhythm == .bed ? "\(percent) percent" : "\(percent) percent, \(mixer.pace(of: orb.kind).rawValue.lowercased())")
        .accessibilityAdjustableAction { direction in
            mixer.adjustVolume(orb.id, by: direction == .increment ? 0.1 : -0.1)
        }
        .accessibilityAction(named: "Remove") { mixer.remove(orb.id) }
        .accessibilityAction(named: "More or less often") { mixer.cyclePace(of: orb.kind) }
    }

    /// The finger `dx` across from where it started: the level moves that much of the width. Past
    /// silent, the layer itself comes away to the left, harder the further, until it's far enough
    /// to remove.
    private func slide(by dx: CGFloat, of width: CGFloat) {
        let start = from ?? orb.volume
        from = start
        let level = start + Double(dx / max(1, width))
        mixer.setVolume(orb.id, to: min(1, max(0, level)))
        let over = level < 0 ? CGFloat(-level) * width : 0
        pull = 120 * tanh(over / 160)
        removing = over > Self.removeAt
    }

    /// Let go (or, not `done`, called off): pulled far enough, the layer goes; otherwise it settles back.
    private func endSlide(_ done: Bool) {
        from = nil
        let remove = removing && done
        removing = false
        if remove {
            Haptics.play(.tap)
            withAnimation(.snappy) { mixer.remove(orb.id) }
        } else {
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { pull = 0 }
        }
    }

    private func bar(width: CGFloat) -> some View {
        let filled = width * CGFloat(orb.volume)
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(LinearGradient(colors: [orb.kind.glow.opacity(0.5), orb.kind.orb.opacity(0.62)],
                                     startPoint: .leading, endPoint: .trailing))
                .background(Theme.background.opacity(0.3))
                .frame(width: filled)
            // The name, and its level and pace centered on the row beside it.
            HStack(alignment: .center) {
                Text(orb.kind.short)
                    .font(Theme.display(height > 64 ? 32 : 24))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 12)
                if orb.kind.rhythm != .bed && !removing {
                    // How often it comes: tap for the next.
                    Button {
                        Haptics.play(.tick)
                        mixer.cyclePace(of: orb.kind)
                    } label: {
                        Text(mixer.pace(of: orb.kind).rawValue.uppercased())
                            .font(Theme.caps(11))
                            .foregroundStyle(Theme.text.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.black.opacity(0.22)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How often: \(mixer.pace(of: orb.kind).rawValue)")
                    .accessibilityHint("Tap for more or less often")
                }
                Text(removing ? "LET GO TO REMOVE" : pull > 4 ? "KEEP PULLING TO REMOVE" : "\(percent)%")
                    .font(Theme.caps(11))
                    .foregroundStyle(Theme.text.opacity(0.85))
            }
            .opacity(removing ? 0.6 : 1)
            .padding(.horizontal, 24)
            .shadow(color: .black.opacity(0.25), radius: 6)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// The last layer, empty: tap it to bring in a sound that belongs here and isn't playing yet. One
/// of this place's own if any are left (owls at the cabin, crickets at the beach), then one like
/// those playing, then any.
private struct AddLayer: View {
    @Environment(Mixer.self) private var mixer
    let height: CGFloat

    var body: some View {
        let playing = Set(mixer.orbs.map(\.kind))
        let waiting = SoundKind.available.filter { !playing.contains($0) }
        let own = mixer.currentCast.filter { !playing.contains($0) }
        let alike = waiting.filter { kind in playing.contains { $0.category == kind.category } }
        Button {
            guard let kind = own.randomElement() ?? alike.randomElement() ?? waiting.randomElement() else { return }
            Haptics.play(.tap)
            withAnimation(.snappy) { mixer.add(kind) }
        } label: {
            Text("+ Add one that fits")
                .font(Theme.display(height > 64 ? 32 : 24))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: height)
        .disabled(waiting.isEmpty)
        .accessibilityLabel("Add a sound that fits")
    }
}

/// Every sound as a pill, in sections: this place's own sounds first, then by kind, with noise
/// last. Each section scrolls sideways; a pill is lit while its sound is playing, and tapping
/// adds it or takes it away. Pills keep their places, so nothing jumps when you tap.
struct SoundSections: View {
    @Environment(Mixer.self) private var mixer
    /// How much of them shows at least (nil: as tall as there's room for, as in the Library).
    static let height: CGFloat = 252
    var height: CGFloat? = Self.height
    /// Inside something that scrolls already, its pills wrapping rather than scrolling sideways
    /// (for a mouse, on the Mac).
    var embedded = false

    var body: some View {
        if embedded {
            sections
        } else {
            ScrollView { sections }
                .scrollIndicators(.hidden)
                .frame(height: height)
                // Fade at the top and bottom edges, so it reads as a list that keeps going.
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                             .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
        }
    }

    private var sections: some View {
        let playing = Set(mixer.orbs.map(\.kind))
        return VStack(alignment: .leading, spacing: 18) {
            if let place = mixer.currentCastPlace, !mixer.currentCast.isEmpty {
                section("Belongs in \(place)", kinds: mixer.currentCast, playing: playing)
            }
            ForEach(SoundKind.Shelf.allCases, id: \.self) { shelf in
                section(shelf.rawValue, kinds: SoundKind.available.filter { $0.shelf == shelf }, playing: playing)
            }
        }
        .padding(.vertical, 12)
    }

    private func section(_ title: String, kinds: [SoundKind], playing: Set<SoundKind>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.caps(10))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)
            if embedded {
                FlowLayout(spacing: 8) {
                    ForEach(kinds) { kind in pill(kind, on: playing.contains(kind)) }
                }
                .padding(.horizontal, 24)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(kinds) { kind in
                            pill(kind, on: playing.contains(kind))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// Lit while it's playing: tap to bring it in (at half its level) or take it away.
    private func pill(_ kind: SoundKind, on: Bool) -> some View {
        Button {
            Haptics.play(.soft)
            withAnimation(.snappy) { on ? mixer.removeAll(kind) : mixer.add(kind) }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(kind.orb).frame(width: 7, height: 7)
                Text(kind.short).font(Theme.body(13, .medium))
            }
            .foregroundStyle(on ? Theme.background : Theme.text)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(Capsule().fill(on ? Theme.text : .clear))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Remove \(kind.name)" : "Add \(kind.name)")
    }
}

extension SoundKind {
    /// Where a sound is filed for browsing: weather apart from water, the jungle with the rest of
    /// nature, the fire with the calm.
    enum Shelf: String, CaseIterable {
        case weather = "Weather", water = "Water", nature = "Nature", night = "Night", city = "City & home",
             calm = "Calm", tones = "Focus tones", noise = "Noise"
    }

    var shelf: Shelf {
        switch self {
        case .rain, .lightRain, .heavyRain, .thunder, .lightning, .tentRain, .tinRoof,
             .wind, .breeze, .treeWind, .gusts, .howl: .weather
        case .ocean, .stream, .waterfall, .caveDrips, .lake, .lapping, .shore, .rocks, .buoy, .halyards,
             .gulls, .foghorn, .whales: .water
        case .birds, .crickets, .cicadas, .frogs, .winterBirds, .geese, .peepers, .palms,
             .howlers, .jungleBirds, .parrots, .canopy, .treeFrogs: .nature
        case .owls, .loons, .wolves, .leaves: .night
        case .cityHum, .cityNight, .train, .steamTrain, .electricTrain, .fan, .cafe, .busyCafe, .library, .cabin, .typing, .clock, .rainyStreet,
             .traffic, .highway, .planes, .tram, .motorbikes, .bazaar, .fountain: .city
        case .chimes, .drone, .bells, .templeBell, .fire: .calm
        case .betaBeats, .gammaBeats, .betaPulse: .tones
        case .brown, .pink, .white, .green, .grey, .blue, .violet: .noise
        }
    }
}

#if os(iOS)
/// A drag across a layer, as UIKit's pan: it only takes hold of a drag that sets off sideways, so one
/// up or down is the list's to scroll. (SwiftUI's own drag holds the list still.)
@available(iOS 18.0, *)
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    /// How far across the finger has gone since it set off.
    let changed: (CGFloat) -> Void
    /// Let go (true) or called off (false).
    let ended: (Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed: changed(pan.translation(in: pan.view).x)
        case .ended: ended(true)
        case .cancelled, .failed: ended(false)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
#endif
