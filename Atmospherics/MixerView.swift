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
        // Laid out for halfway, with the sounds to pick from below, out of sight until it's pulled
        // higher, and then coming up into view under the finger rather than squeezing the layers.
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

    /// What it is and where, and the ways to keep it or put it back.
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LAYERS")
                    .font(Theme.caps(11))
                    .tracking(1.3)
                    .foregroundStyle(Theme.muted)
                Text(mixer.title)
                    .font(Theme.label(15, .medium))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            if mixer.currentPlaceIsTweaked {
                pill("Reset") { resetting = true }
                    .accessibilityLabel("Reset \(mixer.currentPlaceName) to default")
                    .confirmReset(isPresented: $resetting)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            pill("Save") { saving = true }
                .disabled(mixer.orbs.isEmpty)
                .opacity(mixer.orbs.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mixer.currentPlaceIsTweaked ? "Your changes to \(mixer.currentPlaceName) are kept"
                 : "Drag a layer to set it, or to the far left to remove it.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
            if Self.scrolls {
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

    static var scrolls: Bool {
        #if os(iOS)
        if #available(iOS 18.0, *) { return true }
        return false
        #else
        return true
        #endif
    }
}

/// One sound as a layer: filled in its color from the left as far as it's loud, its name large and
/// its level small. Tap anywhere across it to set the level there (it glides over), or drag across
/// to slide it; a drag that starts up or down scrolls the list instead.
private struct LevelRow: View {
    @Environment(Mixer.self) private var mixer
    let orb: Orb
    let height: CGFloat
    @State private var sliding = false
    @State private var taps = 0
    /// Dragged all the way to the left edge: let go there and the layer goes.
    @State private var removing = false

    private var percent: Int { Int((orb.volume * 100).rounded()) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let row = bar(width: width)
                .contentShape(Rectangle())
                .onTapGesture { location in set(location.x, of: width, gliding: true) }
            #if os(iOS)
            if #available(iOS 18.0, *) {
                row.gesture(SidewaysPan { x in slide(to: x, of: width) } ended: { done in endSlide(done) })
            } else {
                row.gesture(DragGesture(minimumDistance: 4)
                    .onChanged { g in slide(to: g.location.x, of: width) }
                    .onEnded { _ in endSlide(true) })
            }
            #else
            row.gesture(DragGesture(minimumDistance: 4)
                .onChanged { g in slide(to: g.location.x, of: width) }
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
        // A tap where you set it, a tick per 10% as it slides, and a landing at the edge where
        // letting go removes it.
        .haptic(.tap, trigger: taps)
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

    private func slide(to x: CGFloat, of width: CGFloat) {
        sliding = true
        removing = x <= width * 0.04
        set(x, of: width, gliding: false)
    }

    /// Let go (or, not `done`, called off): at the far left, the layer goes.
    private func endSlide(_ done: Bool) {
        sliding = false
        guard removing else { return }
        removing = false
        guard done else { return }
        Haptics.play(.tap)
        withAnimation(.snappy) { mixer.remove(orb.id) }
    }

    /// Sets the level to how far across `x` is: gliding there for a tap, straight there as you slide.
    private func set(_ x: CGFloat, of width: CGFloat, gliding: Bool) {
        let to = min(1, max(0, Double(x / max(1, width))))
        if gliding {
            taps += 1
            withAnimation(.snappy(duration: 0.22)) { mixer.setVolume(orb.id, to: to) }
        } else {
            mixer.setVolume(orb.id, to: to)
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
            HStack(alignment: .firstTextBaseline) {
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
                Text(removing ? "LET GO TO REMOVE" : "\(percent)%")
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
    /// How much of them shows at least.
    static let height: CGFloat = 252
    var height: CGFloat = Self.height

    private static let order: [SoundKind.Category] = [.water, .nature, .night, .jungle, .city, .calm, .tones, .noise]

    var body: some View {
        let playing = Set(mixer.orbs.map(\.kind))
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let place = mixer.currentCastPlace, !mixer.currentCast.isEmpty {
                    section(place, kinds: mixer.currentCast, playing: playing)
                }
                ForEach(Self.order, id: \.self) { category in
                    section(category.rawValue, kinds: SoundKind.available.filter { $0.category == category }, playing: playing)
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .frame(height: height)
        // Fade at the top and bottom edges, so it reads as a list that keeps going.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    private func section(_ title: String, kinds: [SoundKind], playing: Set<SoundKind>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.caps(10))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)
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

    private func pill(_ kind: SoundKind, on: Bool) -> some View {
        Button {
            Haptics.play(.tap)
            withAnimation(.snappy) {
                if on {
                    for orb in mixer.orbs where orb.kind == kind { mixer.remove(orb.id) }
                } else {
                    mixer.add(kind)
                }
            }
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

#if os(iOS)
/// A drag across a layer, as UIKit's pan: it only takes hold of a drag that sets off sideways, so one
/// up or down is the list's to scroll. (SwiftUI's own drag holds the list still.)
@available(iOS 18.0, *)
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    /// Where across the layer the finger is.
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
        case .began, .changed: changed(context.converter.localLocation.x)
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
