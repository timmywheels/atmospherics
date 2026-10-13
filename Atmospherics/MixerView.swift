import SwiftUI

#if os(iOS)
/// Topology: the landscape of what's playing, washed in the colors of the mix (`SoundField`), the
/// sound you've picked out of it (`SoundDetail`), and below, every sound to add or take away
/// (`SoundSections`). (On the Mac, `MacTopology` shows the same parts.)
struct MixerView: View {
    @Environment(Mixer.self) private var mixer
    @State private var saving = false
    @State private var resetting = false
    @State private var selected: Orb.ID?

    var body: some View {
        VStack(spacing: 0) {
            SoundField(selected: $selected)

            SoundDetail(selected: $selected,
                        hint: mixer.currentPlaceIsTweaked ? "Your changes to \(mixer.currentPlaceName) are kept"
                            : "Closer is louder · drag the ground to turn it")
                .padding(.bottom, 8)

            SoundSections()
        }
        .foregroundStyle(Theme.text)
        .background { SceneWash(orbs: mixer.orbs) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("TOPOLOGY")
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

/// Topology: what's playing as a landscape, like a raised relief map. Each sound raises a hill
/// where it is, as high as it's loud, drawn in contour lines with its light on top, and you're in
/// the middle, facing the front. Drag a sound closer to hear more of it or off the edge to let it
/// go, tap one to pick it out, and drag the ground to turn the landscape.
struct SoundField: View {
    @Environment(Mixer.self) private var mixer
    @Binding var selected: Orb.ID?
    @State private var yaw = 0.18
    @State private var pitch = 0.66
    @State private var turnStart: (yaw: Double, pitch: Double)?
    /// The sound being dragged off the edge, and where.
    @State private var held: Held?
    @State private var contours = Contours()

    struct Held: Equatable {
        let id: Orb.ID
        var x: Double, z: Double
        var removing: Bool
    }

    /// How much of the view the field is fitted to (see `SculptureCamera.extent`).
    static let extent = 1.02
    /// How far out sounds stand: at full volume, `inner` (leaving you some room), and silent,
    /// `outer`, inside the edge at 1, so even a quiet sound's hill stays on the ground.
    static let inner = 0.2, outer = 0.86
    /// Past this far out, letting go of a sound takes it away.
    static let removeDistance = 1.12

    var body: some View {
        let orbs = mixer.orbs
        let terrain = Terrain(orbs: orbs)
        let lines = contours.lines(for: terrain)
        GeometryReader { proxy in
            let camera = SculptureCamera(yaw: yaw, pitch: pitch, size: proxy.size, extent: Self.extent)
            let lights = Self.lights(orbs, terrain: terrain, camera: camera, held: held)
            ZStack {
                Canvas { ctx, _ in
                    Self.drawGround(ctx, camera, terrain: terrain, lines: lines)
                    Self.drawSounds(ctx, camera, terrain: terrain, lights: lights, selected: selected, held: held)
                }
                .accessibilityHidden(true)
                ForEach(lights) { light in
                    FieldSound(light: light, camera: camera, terrain: terrain, selected: $selected, held: $held)
                        .zIndex(-light.depth)
                }
            }
            .coordinateSpace(.named("field"))
            .contentShape(Rectangle())
            // A tap picks out the nearest light under it (or lets go of it), or anywhere else, nothing.
            .onTapGesture { location in
                let hit = lights.filter { hypot($0.center.x - location.x, $0.center.y - location.y) < 26 }
                    .min { $0.depth < $1.depth }
                withAnimation(.snappy(duration: 0.2)) {
                    if let hit { selected = hit.id == selected ? nil : hit.id } else { selected = nil }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { g in
                        if turnStart == nil { turnStart = (yaw, pitch) }
                        guard let start = turnStart else { return }
                        yaw = start.yaw + g.translation.width * 0.008
                        pitch = min(1.2, max(0.4, start.pitch + g.translation.height * 0.004))
                    }
                    .onEnded { _ in turnStart = nil }
            )
        }
        // A tick every eighth of a turn, and as sounds come and go.
        .sensoryFeedback(.selection, trigger: Int((yaw / (.pi / 8)).rounded(.down)))
        .sensoryFeedback(.impact(weight: .light), trigger: orbs.count)
    }

    // MARK: Where things are

    /// How far out a sound at a volume stands.
    static func reach(forVolume volume: Double) -> Double { inner + (outer - inner) * (1 - volume) }

    /// How loud a sound standing this far out is.
    static func volume(atReach r: Double) -> Double { 1 - min(1, max(0, (r - inner) / (outer - inner))) }

    /// Where a sound stands on the field. The front, toward where we look on from, is -z: the
    /// bottom of the mix's flat field (`Orb.y` toward 1), where new sounds come in.
    static func place(of orb: Orb) -> (x: Double, z: Double) {
        let dx = orb.x - 0.5, dz = 0.5 - orb.y
        let d = hypot(dx, dz)
        let (ux, uz) = d < 0.001 ? (0.0, -1.0) : (dx / d, dz / d)
        let r = reach(forVolume: orb.volume)
        return (ux * r, uz * r)
    }

    /// The other way: for a spot on the field, where the sound goes in the mix.
    static func mixPosition(at x: Double, _ z: Double) -> (x: Double, y: Double) {
        let r = hypot(x, z)
        guard r > 0.001 else { return (0.5, 0.5) }
        let d = max(0.002, (r - inner) / (outer - inner) * 0.5)
        return (0.5 + x / r * d, 0.5 - z / r * d)
    }

    static func lights(_ orbs: [Orb], terrain: Terrain, camera: SculptureCamera, held: Held?) -> [FieldLight] {
        orbs.map { orb in
            var (x, z) = place(of: orb)
            var top = terrain.height(x, z)
            if let held, held.id == orb.id { (x, z, top) = (held.x, held.z, 0) }
            let at = camera.project(x, top, z)
            return FieldLight(orb: orb, x: x, z: z, top: top, anchor: at.point, depth: at.depth,
                              radius: 7 + 3.5 * CGFloat(orb.volume))
        }
    }

    // MARK: Drawing

    private static func point(_ camera: SculptureCamera, _ p: SIMD3<Double>) -> CGPoint {
        camera.project(p.x, p.y, p.z).point
    }

    /// A ring on the ground, flat at a height.
    private static func ring(_ camera: SculptureCamera, radius r: Double, x: Double = 0, z: Double = 0,
                             height h: Double = 0) -> Path {
        var path = Path()
        for i in 0..<72 {
            let a = Double(i) / 72 * 2 * .pi
            let p = point(camera, SIMD3(x + cos(a) * r, h, z + sin(a) * r))
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }

    /// The ground, faintly lit, and its contour lines (faint over the rolling land, clearer up the
    /// hills), all fading out toward the edge, with no line round it; and which way is the front.
    static func drawGround(_ ctx: GraphicsContext, _ camera: SculptureCamera, terrain: Terrain, lines: Contours.Lines) {
        let edge = ring(camera, radius: 1).boundingRect
        var pool = ctx
        pool.translateBy(x: edge.midX, y: edge.midY)
        pool.scaleBy(x: 1, y: edge.height / max(1, edge.width))
        pool.fill(Path(ellipseIn: CGRect(x: -edge.width / 2, y: -edge.width / 2, width: edge.width, height: edge.width)),
                  with: .radialGradient(Gradient(colors: [.white.opacity(0.07), .white.opacity(0.035), .white.opacity(0)]),
                                        center: .zero, startRadius: 0, endRadius: edge.width / 2))
        // Each set of lines in bands by how far out they are, dimmer toward the edge.
        let fades: [(within: Double, opacity: Double)] = [(0.72, 1), (0.82, 0.75), (0.9, 0.5), (0.96, 0.28), (2, 0.12)]
        func stroke(_ segments: [Contours.Segment], opacity: Double, width: CGFloat) {
            var bands = Array(repeating: Path(), count: fades.count)
            for s in segments {
                let r = hypot((s.a.x + s.b.x) / 2, (s.a.z + s.b.z) / 2)
                let band = fades.firstIndex { r < $0.within } ?? fades.count - 1
                bands[band].move(to: point(camera, s.a))
                bands[band].addLine(to: point(camera, s.b))
            }
            for (band, path) in bands.enumerated() {
                ctx.stroke(path, with: .color(Theme.text.opacity(opacity * fades[band].opacity)), lineWidth: width)
            }
        }
        stroke(lines.ground, opacity: 0.2, width: 0.7)
        stroke(lines.hills, opacity: 0.42, width: 0.85)

        // The front, named just past the edge.
        let middle = point(camera, .zero), front = point(camera, SIMD3(0, 0, -1))
        let outward = CGVector(dx: front.x - middle.x, dy: front.y - middle.y)
        let length = max(1, hypot(outward.dx, outward.dy))
        let label = CGPoint(x: front.x + outward.dx / length * 8, y: front.y + outward.dy / length * 8)
        ctx.draw(Text("FRONT").font(Theme.caps(9.5)).tracking(1.6).foregroundStyle(Theme.muted),
                 at: CGPoint(x: min(camera.size.width - 30, max(30, label.x)), y: min(camera.size.height - 10, max(10, label.y))))

        // The way you face: a soft fan of light toward the front.
        let youHeight = terrain.height(0, 0)
        let you = point(camera, SIMD3(0, youHeight, 0))
        var fan = Path()
        fan.move(to: you)
        for i in 0...16 {
            let a = -.pi / 2 - 0.4 + Double(i) / 16 * 0.8
            fan.addLine(to: point(camera, SIMD3(cos(a) * 0.5, youHeight, sin(a) * 0.5)))
        }
        fan.closeSubpath()
        let tip = point(camera, SIMD3(0, youHeight, -0.5))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 7))
            layer.fill(fan, with: .radialGradient(Gradient(colors: [.white.opacity(0.16), .white.opacity(0)]), center: you,
                                                  startRadius: 0, endRadius: hypot(tip.x - you.x, tip.y - you.y)))
        }
    }

    /// Each sound, far ones first: a ring where its hill tops out, its glow, its light; you; and
    /// then every name over the top, each where it covers no light or other name.
    static func drawSounds(_ ctx: GraphicsContext, _ camera: SculptureCamera, terrain: Terrain,
                           lights: [FieldLight], selected: Orb.ID?, held: Held?) {
        let you = point(camera, SIMD3(0, terrain.height(0, 0), 0))
        let ordered = lights.sorted { $0.depth > $1.depth }

        // The way to the sound you've picked, over the ground.
        if let light = lights.first(where: { $0.id == selected }), held?.id != light.id {
            var way = Path()
            for i in 0...32 {
                let t = Double(i) / 32, x = light.x * t, z = light.z * t
                let p = point(camera, SIMD3(x, terrain.height(x, z) + 0.012, z))
                i == 0 ? way.move(to: p) : way.addLine(to: p)
            }
            ctx.stroke(way, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.3, dash: [4, 4]))
        }

        var bases: [Orb.ID: CGRect] = [:]
        for light in ordered {
            let orb = light.orb, r = light.radius
            let removing = held?.id == light.id && held?.removing == true
            let color = removing ? Theme.muted : orb.kind.orb
            let glow = removing ? Theme.muted : orb.kind.glow
            if held?.id != light.id {
                let outer = ring(camera, radius: 0.09, x: light.x, z: light.z, height: light.top)
                ctx.stroke(ring(camera, radius: 0.055, x: light.x, z: light.z, height: light.top),
                           with: .color(glow.opacity(0.95)), lineWidth: 1.3)
                ctx.stroke(outer, with: .color(glow.opacity(0.4)), lineWidth: 1)
                bases[light.id] = outer.boundingRect
            }
            let c = light.center
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: r * 0.9))
                layer.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.8, y: c.y - r * 1.8, width: r * 3.6, height: r * 3.6)),
                           with: .color(glow.opacity(removing ? 0.25 : 0.6)))
            }
            let body = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(body, with: .radialGradient(Gradient(colors: [.white.opacity(0.95), color, glow]),
                                                 center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4),
                                                 startRadius: 0, endRadius: r * 1.6))
            ctx.stroke(body, with: .color(.white.opacity(0.45)), lineWidth: 0.8)
            if removing {
                var cross = Path()
                cross.move(to: CGPoint(x: c.x - 3.5, y: c.y - 3.5)); cross.addLine(to: CGPoint(x: c.x + 3.5, y: c.y + 3.5))
                cross.move(to: CGPoint(x: c.x + 3.5, y: c.y - 3.5)); cross.addLine(to: CGPoint(x: c.x - 3.5, y: c.y + 3.5))
                ctx.stroke(cross, with: .color(Theme.background), lineWidth: 1.6)
            }
            if light.id == selected {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 5, y: c.y - r - 5, width: r * 2 + 10, height: r * 2 + 10)),
                           with: .color(.white.opacity(0.95)), lineWidth: 1.5)
            }
        }

        // You.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.fill(Path(ellipseIn: CGRect(x: you.x - 9, y: you.y - 9, width: 18, height: 18)), with: .color(.white.opacity(0.5)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: you.x - 5, y: you.y - 5, width: 10, height: 10)), with: .color(.white))

        // The names.
        var taken = lights.map { CGRect(x: $0.center.x - $0.radius, y: $0.center.y - $0.radius,
                                        width: $0.radius * 2, height: $0.radius * 2) }
        taken.append(CGRect(x: you.x - 6, y: you.y - 6, width: 12, height: 12))
        taken += bases.values
        let youName = ctx.resolve(Text("You").font(Theme.label(11, .medium)).foregroundStyle(Theme.secondary))
        let youSize = youName.measure(in: CGSize(width: 100, height: 40))
        // Named above you, or below if a light is in the way.
        let youAbove = CGRect(x: you.x - youSize.width / 2, y: you.y - 10 - youSize.height, width: youSize.width, height: youSize.height)
        let youFrame = taken.contains { $0.insetBy(dx: -2, dy: -2).intersects(youAbove) }
            ? youAbove.offsetBy(dx: 0, dy: youSize.height + 19) : youAbove
        taken.append(youFrame)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 3))
            layer.draw(youName, in: youFrame)
            for light in ordered.reversed() {
                let removing = held?.id == light.id && held?.removing == true
                let name = layer.resolve(Text(removing ? "Release to remove" : light.orb.kind.short)
                    .font(Theme.label(11.5, .medium)).foregroundStyle(Theme.text))
                let size = name.measure(in: CGSize(width: 240, height: 40))
                let c = light.center, r = light.radius
                let gap = r + (light.id == selected ? 8 : 4)
                let above = CGRect(x: c.x - size.width / 2, y: c.y - gap - size.height, width: size.width, height: size.height)
                let base = bases[light.id] ?? CGRect(origin: light.anchor, size: .zero)
                let below = CGRect(x: c.x - size.width / 2, y: max(light.anchor.y + 7, base.maxY + 3), width: size.width, height: size.height)
                let right = CGRect(x: c.x + gap + 2, y: c.y - size.height / 2, width: size.width, height: size.height)
                let left = CGRect(x: c.x - gap - 2 - size.width, y: c.y - size.height / 2, width: size.width, height: size.height)
                // Far ones are named above, near ones below, unless that covers something.
                let frames = light.depth > 0 ? [above, below, right, left] : [below, above, right, left]
                let own = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                let frame = frames.first { f in
                    !taken.contains { $0 != own && $0 != base && $0.insetBy(dx: -2, dy: -1).intersects(f) }
                }
                    ?? frames[0]
                taken.append(frame)
                layer.draw(name, in: frame)
            }
        }
    }
}

/// A sound as the field draws it: where its hill is, how high the ground is there, and on
/// screen, where its hill tops out (`anchor`) and its light sits just above.
struct FieldLight: Identifiable {
    let orb: Orb
    let x: Double, z: Double
    let top: Double
    let anchor: CGPoint
    let depth: Double
    let radius: CGFloat
    var id: Orb.ID { orb.id }
    var center: CGPoint { CGPoint(x: anchor.x, y: anchor.y - radius) }
}

/// The ground: a hill under each sound, as high as it's loud, on gently rolling land.
struct Terrain {
    struct Hill { let id: Orb.ID, x: Double, z: Double, height: Double, foot: Double }
    let hills: [Hill]

    init(orbs: [Orb]) {
        hills = orbs.map { orb in
            let p = SoundField.place(of: orb)
            return Hill(id: orb.id, x: p.x, z: p.z, height: Self.hill(forVolume: orb.volume), foot: Self.foot(forVolume: orb.volume))
        }
    }

    /// How high a sound's hill is, and how far its foot spreads.
    static func hill(forVolume v: Double) -> Double { 0.08 + 0.4 * v }
    static func foot(forVolume v: Double) -> Double { 0.2 + 0.16 * v }

    func height(_ x: Double, _ z: Double, without id: Orb.ID? = nil) -> Double {
        // The land between rolls in long, slow swells.
        let ground = 0.02 + 0.012 * sin(2.3 * x + 1.1 * z + 0.5) + 0.01 * cos(1.7 * x - 2.9 * z + 1.3)
            + 0.008 * sin(3.1 * x + 0.7 * z - 2)
        return hills.reduce(ground) { h, hill in
            guard hill.id != id else { return h }
            // A smooth mound that comes down to the ground at its foot, so each hill keeps to itself.
            let t = ((x - hill.x) * (x - hill.x) + (z - hill.z) * (z - hill.z)) / (hill.foot * hill.foot)
            return t < 1 ? h + hill.height * (1 - t) * (1 - t) : h
        }
    }

    /// Changes whenever the ground does.
    var key: [Double] { hills.flatMap { [$0.x, $0.z, $0.height] } }
}

/// Contour lines over the ground, as on a topographic map: loops of equal height (marching squares
/// over the height field), each at its own height so they stack up every hill. Traced again only
/// when the ground changes, not as it turns.
final class Contours {
    struct Segment { let a: SIMD3<Double>, b: SIMD3<Double> }
    struct Lines { var ground: [Segment] = [], hills: [Segment] = [] }

    private var key: [Double]?
    private var traced = Lines()

    func lines(for terrain: Terrain) -> Lines {
        let key = terrain.key
        if key != self.key {
            self.key = key
            traced = Self.trace(terrain)
        }
        return traced
    }

    /// Which edges of a grid cell a contour crosses, for each pattern of corners above the level
    /// (bit 0: the cell's first corner, then around: 1, 2, 3). Edges: 0 bottom, 1 right, 2 top, 3 left.
    private static let crossings: [[(Int, Int)]] = [
        [], [(3, 0)], [(0, 1)], [(3, 1)], [(1, 2)], [(3, 0), (1, 2)], [(0, 2)], [(2, 3)],
        [(2, 3)], [(0, 2)], [(0, 1), (2, 3)], [(1, 2)], [(1, 3)], [(0, 1)], [(3, 0)], [],
    ]

    private static func trace(_ terrain: Terrain) -> Lines {
        let n = 90, e = 1.0
        func coordinate(_ i: Int) -> Double { -e + 2 * e * Double(i) / Double(n) }
        var heights = [Double](repeating: 0, count: (n + 1) * (n + 1))
        for i in 0...n {
            for j in 0...n { heights[i * (n + 1) + j] = terrain.height(coordinate(i), coordinate(j)) }
        }
        let groundLevels = [0.0, 0.017, 0.034]
        let hillLevels = Array(stride(from: 0.06, through: 1.2, by: 0.062))
        var lines = Lines()
        for i in 0..<n {
            for j in 0..<n {
                let x0 = coordinate(i), x1 = coordinate(i + 1), z0 = coordinate(j), z1 = coordinate(j + 1)
                let reach = max(x0 * x0, x1 * x1) + max(z0 * z0, z1 * z1)
                guard reach <= e * e else { continue }
                let corners = [(x0, z0, heights[i * (n + 1) + j]), (x1, z0, heights[(i + 1) * (n + 1) + j]),
                               (x1, z1, heights[(i + 1) * (n + 1) + j + 1]), (x0, z1, heights[i * (n + 1) + j + 1])]
                let low = corners.map(\.2).min()!, high = corners.map(\.2).max()!
                func contour(at level: Double, into segments: inout [Segment]) {
                    guard low < level, high >= level else { return }
                    var pattern = 0
                    for (bit, c) in corners.enumerated() where c.2 >= level { pattern |= 1 << bit }
                    func crossing(_ edge: Int) -> SIMD3<Double> {
                        let a = corners[edge], b = corners[(edge + 1) % 4]
                        let t = (level - a.2) / (b.2 - a.2)
                        return SIMD3(a.0 + t * (b.0 - a.0), level, a.1 + t * (b.1 - a.1))
                    }
                    for (from, to) in crossings[pattern] {
                        segments.append(Segment(a: crossing(from), b: crossing(to)))
                    }
                }
                if reach <= 0.96 {
                    for level in groundLevels { contour(at: level, into: &lines.ground) }
                }
                for level in hillLevels where level <= high { contour(at: level, into: &lines.hills) }
            }
        }
        return lines
    }
}

/// A sound's light, to take hold of: drag it to move its hill (closer is louder), out past the edge
/// to let it go. (Tapping one to pick it out is the field's.)
private struct FieldSound: View {
    @Environment(Mixer.self) private var mixer
    let light: FieldLight
    let camera: SculptureCamera
    let terrain: Terrain
    @Binding var selected: Orb.ID?
    @Binding var held: SoundField.Held?
    /// From the finger to the top of the hill, as the drag began, so the light doesn't jump.
    @State private var grab: CGSize?

    var body: some View {
        let pct = Int((light.orb.volume * 100).rounded())
        let removing = held?.id == light.id && held?.removing == true

        Color.clear
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(light.center)
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("field"))
                    .onChanged { g in
                        if grab == nil {
                            grab = CGSize(width: light.anchor.x - g.startLocation.x, height: light.anchor.y - g.startLocation.y)
                            selected = light.id
                        }
                        guard let grab else { return }
                        let at = CGPoint(x: g.location.x + grab.width, y: g.location.y + grab.height)
                        guard let p = spot(under: at) else { return }
                        let out = hypot(p.x, p.z)
                        held = out > 1 ? SoundField.Held(id: light.id, x: p.x, z: p.z, removing: out > SoundField.removeDistance) : nil
                        let mix = SoundField.mixPosition(at: p.x, p.z)
                        mixer.move(light.id, toX: mix.x, y: mix.y)
                    }
                    .onEnded { _ in
                        if held?.id == light.id, held?.removing == true {
                            withAnimation(.snappy) { mixer.remove(light.id) }
                            selected = nil
                        }
                        held = nil
                        grab = nil
                    }
            )
            // A soft tap on pickup, a tick per 10% of volume, and a firm snap when it's ready to remove.
            .sensoryFeedback(.impact(flexibility: .soft), trigger: grab != nil) { _, holding in holding }
            .sensoryFeedback(.selection, trigger: pct / 10) { _, _ in grab != nil && held == nil }
            .sensoryFeedback(.impact(weight: .heavy), trigger: removing) { _, now in now }
            .accessibilityElement()
            .accessibilityLabel(light.orb.kind.name)
            .accessibilityValue("\(pct) percent")
            .accessibilityAdjustableAction { direction in
                mixer.adjustVolume(light.id, by: direction == .increment ? 0.1 : -0.1)
            }
            .accessibilityAction(named: "Remove") { mixer.remove(light.id) }
    }

    /// The spot on the field whose hilltop is under a point on screen. The hill grows as the sound
    /// comes closer, so it's found in a few steps, each looking at the height the last one gave.
    private func spot(under at: CGPoint) -> (x: Double, z: Double)? {
        var level = light.top
        var spot = camera.ground(under: at, height: level)
        for _ in 0..<3 {
            guard let p = spot else { return nil }
            let r = hypot(p.x, p.z)
            level = r > 1 ? 0 : terrain.height(p.x, p.z, without: light.id) + Terrain.hill(forVolume: SoundField.volume(atReach: r))
            spot = camera.ground(under: at, height: level)
        }
        return spot
    }
}

/// Under the field: a way to take away the sound you've picked out, or else a word on how the
/// field works.
struct SoundDetail: View {
    @Environment(Mixer.self) private var mixer
    @Binding var selected: Orb.ID?
    let hint: String

    var body: some View {
        ZStack {
            if let id = selected, let orb = mixer.orbs.first(where: { $0.id == id }) {
                Button {
                    withAnimation(.snappy) { mixer.remove(orb.id) }
                    selected = nil
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        Text("Remove \(orb.kind.short)").font(Theme.label(12, .medium))
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 14)
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Text(hint)
                    .font(Theme.label(10.5))
                    .foregroundStyle(Theme.muted)
                    .transition(.opacity)
            }
        }
        .frame(height: 34)
        .animation(.smooth(duration: 0.2), value: selected)
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
