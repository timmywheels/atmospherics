import SwiftUI

#if os(iOS)
/// Layers: a landscape of what's playing, washed in the colors of the mix. Each sound raises a
/// hill where it sits, as high as it is loud, and you're at the center: drag a sound closer to
/// hear more of it, out past the rim to let it go, and drag the ground to turn the landscape.
/// The sections below add a sound or take it away. (On the Mac, `MacLayers` shows the same parts.)
struct MixerView: View {
    @Environment(Mixer.self) private var mixer
    @State private var saving = false
    @State private var resetting = false

    var body: some View {
        VStack(spacing: 0) {
            TerrainField()

            Text(mixer.currentPlaceIsTweaked
                 ? "Your changes to \(mixer.currentPlaceName) are kept"
                 : "Closer is louder · drag the ground to turn it")
                .font(Theme.label(10.5))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 14)

            SoundSections()
        }
        .foregroundStyle(Theme.text)
        .background { SceneWash(orbs: mixer.orbs) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("LAYERS")
                    .font(Theme.caps(11))
                    .tracking(1.3)
                    .foregroundStyle(Theme.muted)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if mixer.currentPlaceIsTweaked {
                    Button { resetting = true } label: {
                        Text("Reset").font(Theme.label(12, .medium))
                    }
                    .accessibilityLabel("Reset \(mixer.currentPlaceName) to default")
                }
                Button { saving = true } label: {
                    Text("Save").font(Theme.label(12, .medium))
                }
                .disabled(mixer.orbs.isEmpty)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .saveMixPrompt(isPresented: $saving)
        .confirmReset(isPresented: $resetting)
    }
}
#endif

/// The landscape: the sculpture of what's playing, standing on the field's ground with contour
/// footprints, the rim dashed and you marked at the middle. Drag the ground to turn and tilt it;
/// drag a sound to move it, closer to hear more of it, past the rim to let it go.
struct TerrainField: View {
    @Environment(Mixer.self) private var mixer
    @State private var yaw = -0.4
    @State private var pitch = 0.82
    @State private var turnStart: (yaw: Double, pitch: Double)?

    var body: some View {
        GeometryReader { proxy in
            let camera = SculptureCamera(yaw: yaw, pitch: pitch, size: proxy.size)
            let you = camera.project(0, 0, 0).point
            let shifts = Self.labelShifts(mixer.orbs, camera: camera)
            ZStack {
                SculptureView(orbs: mixer.orbs, style: .layers, yaw: yaw, pitch: pitch, ground: true, animated: false)
                Text("you")
                    .font(Theme.label(10))
                    .foregroundStyle(Theme.muted)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .position(x: you.x, y: you.y + 16)
                    .allowsHitTesting(false)
                ForEach(mixer.orbs) { orb in
                    TerrainOrb(orb: orb, camera: camera, labelShift: shifts[orb.id] ?? 0)
                }
            }
            .coordinateSpace(name: "terrain")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { g in
                        if turnStart == nil { turnStart = (yaw, pitch) }
                        guard let start = turnStart else { return }
                        yaw = start.yaw + g.translation.width * 0.008
                        pitch = min(1.35, max(0.5, start.pitch + g.translation.height * 0.004))
                    }
                    .onEnded { _ in turnStart = nil }
            )
        }
        // A tick every eighth of a turn.
        .sensoryFeedback(.selection, trigger: Int((yaw / (.pi / 8)).rounded(.down)))
        .sensoryFeedback(.impact(weight: .light), trigger: mixer.orbs.count)
    }

    /// Where each name goes: under its sound, nudged down past any louder sound's name it would cover.
    static func labelShifts(_ orbs: [Orb], camera: SculptureCamera) -> [Orb.ID: CGFloat] {
        var placed: [CGRect] = []
        var shifts: [Orb.ID: CGFloat] = [:]
        for orb in orbs.sorted(by: { $0.volume > $1.volume }) {
            let body = SculptureStyle.layers.body(of: orb, at: 0)
            let spot = camera.project(body.center.x, body.center.y, body.center.z)
            let below = body.radius * camera.scale(atDepth: spot.depth) + 12
            let width = CGFloat(orb.kind.short.count) * 7 + 12
            var rect = CGRect(x: spot.point.x - width / 2, y: spot.point.y + below - 7, width: width, height: 14)
            var shift: CGFloat = 0
            while placed.contains(where: { $0.intersects(rect) }), shift < 60 {
                shift += 14
                rect.origin.y += 14
            }
            placed.append(rect)
            shifts[orb.id] = shift
        }
        return shifts
    }
}

/// A sound on the landscape: something to take hold of over its body, named underneath.
private struct TerrainOrb: View {
    @Environment(Mixer.self) private var mixer
    let orb: Orb
    let camera: SculptureCamera
    var labelShift: CGFloat = 0
    @State private var dragging = false
    /// The level the finger moves the sound across, fixed when the drag begins.
    @State private var dragHeight: Double?
    /// Where the finger is on the ground while it's past the rim.
    @State private var outside: (x: Double, z: Double)?

    /// Past this distance from center (the rim is 1), letting go removes the sound.
    private static let removeDistance = 1.36

    private var removing: Bool {
        guard let p = outside else { return false }
        return hypot(p.x, p.z) > Self.removeDistance
    }

    var body: some View {
        let body = SculptureStyle.layers.body(of: orb, at: 0)
        let projected = camera.project(body.center.x, body.center.y, body.center.z)
        let spot = outside.map { camera.project($0.x, 0, $0.z) } ?? projected
        let radius = body.radius * camera.scale(atDepth: projected.depth)
        let size = max(44, radius * 2)
        let pct = Int((orb.volume * 100).rounded())

        ZStack {
            // Out past the rim, the sound's body stays at the edge; a ghost follows the finger.
            if outside != nil {
                Circle()
                    .strokeBorder(removing ? Theme.text : Theme.muted, lineWidth: 1.2)
                    .background(Circle().fill(.black.opacity(0.25)))
                    .frame(width: 22, height: 22)
                if removing {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Text(removing ? "Release to remove"
                 : outside != nil ? "Drag further to remove"
                 : dragging ? "\(orb.kind.short) \(pct)" : orb.kind.short)
                .font(Theme.label(10, .medium))
                .foregroundStyle(removing ? Theme.text : Theme.orbLabel)
                .shadow(color: .black.opacity(0.7), radius: 3)
                .fixedSize()
                .offset(y: (outside != nil ? 22 : radius + 12) + (outside != nil ? 0 : labelShift))
                .allowsHitTesting(false)
        }
        .contentShape(Circle())
        .position(spot.point)
        .zIndex(dragging ? 1000 : -spot.depth)
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("terrain"))
                .onChanged { g in
                    if dragHeight == nil { dragHeight = body.center.y }
                    guard let h = dragHeight, let p = camera.ground(under: g.location, height: h) else { return }
                    dragging = true
                    outside = hypot(p.x, p.z) > 1 ? p : nil
                    mixer.move(orb.id, toX: p.x / 2 + 0.5, y: p.z / 2 + 0.5)
                }
                .onEnded { _ in
                    if removing {
                        withAnimation(.snappy) { mixer.remove(orb.id) }
                    } else {
                        withAnimation(.spring(duration: 0.35, bounce: 0.35)) { outside = nil }
                    }
                    dragging = false
                    dragHeight = nil
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.snappy) { mixer.remove(orb.id) }
        }
        .animation(.snappy(duration: 0.2), value: dragging)
        .animation(.snappy(duration: 0.18), value: removing)
        // A soft tap on pickup, a tick per 10% of volume, and a firm snap when it's ready to remove.
        .sensoryFeedback(.impact(flexibility: .soft), trigger: dragging) { _, isDragging in isDragging }
        .sensoryFeedback(.selection, trigger: pct / 10) { _, _ in dragging && outside == nil }
        .sensoryFeedback(.impact(weight: .heavy), trigger: removing) { _, now in now }
        .accessibilityElement()
        .accessibilityLabel(orb.kind.name)
        .accessibilityValue("\(pct) percent")
        .accessibilityAdjustableAction { direction in
            mixer.adjustVolume(orb.id, by: direction == .increment ? 0.1 : -0.1)
        }
        .accessibilityAction(named: "Remove") { mixer.remove(orb.id) }
    }
}

/// Every sound as a pill, in sections: this place's own sounds first, then by kind, with noise
/// last. Each section scrolls sideways; a pill is lit while its sound is playing, and tapping
/// adds it or takes it away. Pills keep their places, so nothing jumps when you tap.
struct SoundSections: View {
    @Environment(Mixer.self) private var mixer

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
        .frame(height: 252)
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
            Haptics.tap(.light)
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
