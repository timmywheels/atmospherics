import SwiftUI

/// Layers: a landscape of what's playing, washed in the colors of the mix. Each sound raises a
/// hill where it sits, as high as it is loud, and you're at the center: drag a sound closer to
/// hear more of it, out past the rim to let it go, and drag the ground to turn the landscape.
/// The sections below add a sound or take it away.
struct MixerView: View {
    @Environment(Mixer.self) private var mixer
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            TerrainField()

            Text(mixer.currentPlaceIsTweaked
                 ? "Your changes to \(mixer.currentPlaceName) are kept"
                 : "Closer is louder · drag the ground to turn it")
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.mono)
                .padding(.bottom, 14)

            SoundSections()
        }
        .foregroundStyle(Theme.text)
        .background { SceneWash(orbs: mixer.orbs) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("LAYERS")
                    .font(Theme.mono(11, .medium))
                    .tracking(1.3)
                    .foregroundStyle(Theme.mono)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if mixer.currentPlaceIsTweaked {
                    Button { withAnimation(.smooth) { mixer.resetCurrentPlace() } } label: {
                        Text("Reset").font(Theme.mono(12, .medium))
                    }
                    .accessibilityLabel("Reset \(mixer.currentPlaceName) to default")
                }
                Button { saving = true } label: {
                    Text("Save").font(Theme.mono(12, .medium))
                }
                .disabled(mixer.orbs.isEmpty)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .saveMixPrompt(isPresented: $saving)
    }
}

/// How the landscape is seen: turned (yaw), tilted (pitch, 0 is side on), in perspective.
/// The ground is the field's disc, radius 1 at the rim, with height going up.
private struct Camera {
    var yaw: Double
    var pitch: Double
    let size: CGSize
    static let distance = 3.4
    /// The ground reaches a little past the rim.
    static let extent = 1.12

    private var focal: Double { (Double(size.width) / 2 - 18) * Self.distance / Self.extent }
    private var center: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.5) }

    func project(_ x: Double, _ y: Double, _ z: Double) -> (point: CGPoint, depth: Double) {
        let x1 = x * cos(yaw) - z * sin(yaw)
        let z1 = x * sin(yaw) + z * cos(yaw)
        let y2 = y * cos(pitch) + z1 * sin(pitch)
        let z2 = -y * sin(pitch) + z1 * cos(pitch)
        let s = focal / (Self.distance + z2)
        return (CGPoint(x: center.x + x1 * s, y: center.y - y2 * s), z2)
    }

    /// The spot at height `h` that's under a point on screen.
    func ground(under p: CGPoint, height h: Double) -> (x: Double, z: Double)? {
        let a = (p.x - center.x) / focal, b = (center.y - p.y) / focal
        let denominator = b * cos(pitch) - sin(pitch)
        guard abs(denominator) > 1e-4 else { return nil }
        let z1 = (h * cos(pitch) - b * (Self.distance - h * sin(pitch))) / denominator
        let z2 = -h * sin(pitch) + z1 * cos(pitch)
        let x1 = a * (Self.distance + z2)
        return (x1 * cos(yaw) + z1 * sin(yaw), -x1 * sin(yaw) + z1 * cos(yaw))
    }
}

/// The ground: a hill under each sound, as high as it is loud, colored by whichever sound is
/// nearest and strongest.
private struct Terrain {
    struct Peak { let x: Double, z: Double, height: Double, kind: SoundKind }
    let peaks: [Peak]

    init(orbs: [Orb]) {
        peaks = orbs.map { Peak(x: ($0.x - 0.5) * 2, z: ($0.y - 0.5) * 2, height: 0.72 * pow($0.volume, 1.1), kind: $0.kind) }
    }

    func height(_ x: Double, _ z: Double) -> Double {
        peaks.reduce(0) { h, p in h + p.height * exp(-((x - p.x) * (x - p.x) + (z - p.z) * (z - p.z)) / 0.075) }
    }

    func owner(_ x: Double, _ z: Double) -> (index: Int, strength: Double)? {
        var best: (index: Int, strength: Double)?
        for (i, p) in peaks.enumerated() {
            let w = (0.25 + p.height) * exp(-((x - p.x) * (x - p.x) + (z - p.z) * (z - p.z)) / 0.16)
            if w > (best?.strength ?? 0) { best = (i, w) }
        }
        return best
    }
}

/// The landscape: a fine mesh over the disc, lit in each sound's color around its hill, with
/// the rim dashed and you marked at the center. Drag the ground to turn and tilt it.
private struct TerrainField: View {
    @Environment(Mixer.self) private var mixer
    @State private var yaw = -0.4
    @State private var pitch = 0.82
    @State private var turnStart: (yaw: Double, pitch: Double)?

    var body: some View {
        GeometryReader { proxy in
            let camera = Camera(yaw: yaw, pitch: pitch, size: proxy.size)
            let terrain = Terrain(orbs: mixer.orbs)
            let you = camera.project(0, terrain.height(0, 0), 0).point
            ZStack {
                Canvas { ctx, _ in draw(terrain, camera, in: &ctx) }
                    .accessibilityHidden(true)
                Text("you")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.mono)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .position(x: you.x, y: you.y + 18)
                    .allowsHitTesting(false)
                ForEach(mixer.orbs) { orb in
                    TerrainOrb(orb: orb, camera: camera, terrain: terrain)
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

    private func draw(_ terrain: Terrain, _ camera: Camera, in ctx: inout GraphicsContext) {
        // A round mesh: rings around you and spokes out to the edge, so the hills bend the rings
        // like contour lines and the ground ends in a clean circle.
        let rings = 28, spokes = 56, e = Camera.extent
        func spot(_ k: Int, _ m: Int) -> (x: Double, z: Double) {
            let r = e * Double(k) / Double(rings), a = Double(m) / Double(spokes) * 2 * .pi
            return (r * cos(a), r * sin(a))
        }
        var points = [CGPoint](repeating: .zero, count: (rings + 1) * spokes)
        var heights = [Double](repeating: 0, count: (rings + 1) * spokes)
        for k in 1...rings {
            for m in 0..<spokes {
                let (x, z) = spot(k, m), i = k * spokes + m
                heights[i] = terrain.height(x, z)
                points[i] = camera.project(x, heights[i], z).point
            }
        }

        // Plain ground in a faint line, fainter still toward the edge; around each hill, its
        // sound's color, brighter higher up.
        var plain = Path(), fringe = Path()
        var lit = Array(repeating: Array(repeating: Path(), count: 4), count: terrain.peaks.count)
        func edge(_ a: Int, _ b: Int, _ x: Double, _ z: Double, outer: Bool) {
            if let owner = terrain.owner(x, z), owner.strength > 0.18 {
                let level = min(3, Int((heights[a] + heights[b]) / 2 / 0.1))
                lit[owner.index][level].move(to: points[a])
                lit[owner.index][level].addLine(to: points[b])
            } else if outer {
                fringe.move(to: points[a])
                fringe.addLine(to: points[b])
            } else {
                plain.move(to: points[a])
                plain.addLine(to: points[b])
            }
        }
        for k in 1...rings {
            for m in 0..<spokes {
                let (x, z) = spot(k, m), i = k * spokes + m
                edge(i, k * spokes + (m + 1) % spokes, x, z, outer: k > rings - 3)
                // Spokes start a little way out, so they don't crowd together around you.
                if k >= 5 && k < rings { edge(i, (k + 1) * spokes + m, x, z, outer: k + 1 > rings - 3) }
            }
        }
        ctx.stroke(plain, with: .color(.white.opacity(0.09)), lineWidth: 0.6)
        ctx.stroke(fringe, with: .color(.white.opacity(0.045)), lineWidth: 0.6)
        ctx.drawLayer { glow in
            glow.addFilter(.blur(radius: 5))
            for (i, paths) in lit.enumerated() {
                for level in 2..<4 { glow.stroke(paths[level], with: .color(terrain.peaks[i].kind.glow.opacity(0.7)), lineWidth: 2.5) }
            }
        }
        for (i, paths) in lit.enumerated() {
            for level in 0..<4 {
                ctx.stroke(paths[level], with: .color(terrain.peaks[i].kind.orb.opacity([0.28, 0.45, 0.65, 0.9][level])),
                           lineWidth: [0.7, 0.85, 1, 1.2][level])
            }
        }

        // The rim, where a sound falls silent, following the ground.
        var rim = Path()
        for step in 0...120 {
            let a = Double(step) / 120 * 2 * .pi
            let p = camera.project(cos(a), terrain.height(cos(a), sin(a)), sin(a)).point
            step == 0 ? rim.move(to: p) : rim.addLine(to: p)
        }
        ctx.stroke(rim, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))

        // You, at the center.
        var ring = Path()
        for step in 0...48 {
            let a = Double(step) / 48 * 2 * .pi, x = 0.075 * cos(a), z = 0.075 * sin(a)
            let p = camera.project(x, terrain.height(x, z), z).point
            step == 0 ? ring.move(to: p) : ring.addLine(to: p)
        }
        ctx.stroke(ring, with: .color(Theme.text.opacity(0.8)), lineWidth: 1.2)
        let you = camera.project(0, terrain.height(0, 0), 0).point
        ctx.fill(Path(ellipseIn: CGRect(x: you.x - 3, y: you.y - 3, width: 6, height: 6)), with: .color(Theme.text))
    }
}

/// A sound on the landscape: a soft light at the top of its hill, named underneath.
private struct TerrainOrb: View {
    @Environment(Mixer.self) private var mixer
    let orb: Orb
    let camera: Camera
    let terrain: Terrain
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
        let v = orb.volume
        let x = (orb.x - 0.5) * 2, z = (orb.y - 0.5) * 2
        let spot = outside.map { camera.project($0.x, 0, $0.z) } ?? camera.project(x, terrain.height(x, z) + 0.03, z)
        let glow = 26 + v * 30
        let core = 7 + v * 5
        let pct = Int((v * 100).rounded())

        ZStack {
            Circle()
                .fill((removing ? Theme.mono : orb.kind.halo).opacity(removing ? 0.4 : 0.85))
                .frame(width: glow, height: glow)
                .blur(radius: glow * 0.25)
            Circle()
                .fill(removing ? Theme.mono : orb.kind.orb)
                .frame(width: core, height: core)
                .shadow(color: orb.kind.glow, radius: removing ? 0 : 6)
            if removing {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.background)
            }
        }
        .scaleEffect(removing ? 0.8 : dragging ? 1.15 : 1)
        .frame(width: 52, height: 52)
        .overlay {
            Text(removing ? "Release to remove"
                 : outside != nil ? "Drag further to remove"
                 : dragging ? "\(orb.kind.short) \(pct)" : orb.kind.short)
                .font(Theme.mono(10, .medium))
                .foregroundStyle(removing ? Theme.text : Theme.orbLabel)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .fixedSize()
                .offset(y: core / 2 + 12)
                .allowsHitTesting(false)
        }
        .contentShape(Circle())
        .position(spot.point)
        .zIndex(dragging ? 1000 : -spot.depth)
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("terrain"))
                .onChanged { g in
                    if dragHeight == nil { dragHeight = terrain.height(x, z) }
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
private struct SoundSections: View {
    @Environment(Mixer.self) private var mixer

    private static let order: [SoundKind.Category] = [.water, .nature, .night, .jungle, .city, .calm, .noise]

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
                .font(Theme.mono(10, .medium))
                .tracking(1.2)
                .foregroundStyle(Theme.mono)
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
