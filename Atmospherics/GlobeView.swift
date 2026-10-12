import SwiftUI

/// The world: a glowing globe to spin and pick a place from, or a list by region.
struct GlobeView: View {
    @Environment(Mixer.self) private var mixer
    @Environment(\.dismiss) private var dismiss
    @State private var showList = false
    @State private var focused: Place?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("World")
                    .font(Theme.display(30))
                    .tracking(-0.6)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 24)

            HStack(spacing: 8) {
                pill("Globe", selected: !showList) { showList = false }
                pill("List", selected: showList) { showList = true }
                Spacer()
                pill(mixer.pinnedPlace == nil ? "Most different ✓" : "Most different", selected: false) {
                    mixer.unpinPlace()
                    dismiss()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            if showList {
                PlaceList { listen($0) }
                    .padding(.top, 12)
            } else {
                GlobeCanvas(focused: $focused)
                    .padding(.top, 8)
                PlaceCard(place: focused ?? mixer.escape?.place ?? Place.all[0]) { listen($0) }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .padding(.top, 24)
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: showList)
    }

    private func listen(_ place: Place) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        mixer.select(place)
        dismiss()
    }

    private func pill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.body(13, .medium))
                .foregroundStyle(selected ? Theme.background : Theme.text)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Capsule().fill(selected ? Theme.text : .clear))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Globe

/// Rotation state, advanced each frame. A class so the Canvas can read it
/// without every frame becoming a SwiftUI state change.
private final class GlobeMotion {
    var longitude: Double = -40      // center of view, degrees
    var latitude: Double = 20
    var velocity: Double = 0         // degrees per second, around the vertical axis
    var target: (lon: Double, lat: Double)?
    var dragging = false
    var lastFrame: Date?
    var idleSince = Date()
}

private struct GlobeCanvas: View {
    @Environment(Mixer.self) private var mixer
    @Binding var focused: Place?
    @State private var motion = GlobeMotion()
    @State private var dragStart: (lon: Double, lat: Double)?
    @State private var shuffles = 0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let radius = min(size.width, size.height) / 2 * 0.86
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            ZStack(alignment: .bottomTrailing) {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, _ in
                        draw(&ctx, center: center, radius: radius, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                    .onChange(of: timeline.date) { _, now in step(now) }
                }
                .contentShape(Rectangle())
                .gesture(drag(radius: radius))
                .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                    if let place = hit(tap.location, center: center, radius: radius) { fly(to: place) }
                })

                Button { shuffle() } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(Theme.mono(12, .medium))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Capsule().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .padding(20)
            }
        }
        .sensoryFeedback(.selection, trigger: focused)
        .sensoryFeedback(.impact(weight: .medium), trigger: shuffles)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Globe. Use the list for VoiceOver.")
        .onAppear {
            if let current = mixer.escape?.place {
                motion.longitude = current.longitude
                motion.latitude = max(-50, min(50, current.latitude))
                focused = current
            }
        }
    }

    // MARK: Motion

    private func step(_ now: Date) {
        let dt = min(1 / 20, now.timeIntervalSince(motion.lastFrame ?? now))
        motion.lastFrame = now
        if let target = motion.target {
            // Ease toward a chosen city, taking the short way round.
            var dLon = (target.lon - motion.longitude).truncatingRemainder(dividingBy: 360)
            if dLon > 180 { dLon -= 360 } else if dLon < -180 { dLon += 360 }
            motion.longitude += dLon * min(1, dt * 4)
            motion.latitude += (target.lat - motion.latitude) * min(1, dt * 4)
            if abs(dLon) < 0.2 && abs(target.lat - motion.latitude) < 0.2 { motion.target = nil }
        } else if !motion.dragging {
            motion.longitude -= motion.velocity * dt
            motion.velocity *= pow(0.12, dt)   // momentum fades over about a second
            // After a few seconds idle, turn slowly on its own.
            if abs(motion.velocity) < 1 && now.timeIntervalSince(motion.idleSince) > 4 {
                motion.longitude += 3 * dt
            }
        }
        // While spinning freely, whichever city passes under the center becomes the focus.
        if motion.target == nil, let nearest = nearestToCenter(), nearest != focused { focused = nearest }
    }

    private func drag(radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                if dragStart == nil {
                    dragStart = (motion.longitude, motion.latitude)
                    motion.dragging = true
                    motion.target = nil
                }
                // Moving a finger across the full radius turns the globe about 90°.
                let degreesPerPoint = 90 / Double(radius)
                motion.longitude = dragStart!.lon - Double(g.translation.width) * degreesPerPoint
                motion.latitude = max(-60, min(60, dragStart!.lat + Double(g.translation.height) * degreesPerPoint))
            }
            .onEnded { g in
                let degreesPerPoint = 90 / Double(radius)
                motion.velocity = Double(g.velocity.width) * degreesPerPoint
                motion.dragging = false
                motion.idleSince = Date()
                dragStart = nil
            }
    }

    private func fly(to place: Place) {
        motion.target = (place.longitude, max(-60, min(60, place.latitude)))
        motion.velocity = 0
        motion.idleSince = Date()
        focused = place
    }

    private func shuffle() {
        let options = Place.all.filter { $0 != focused }
        guard let place = options.randomElement() else { return }
        shuffles += 1
        fly(to: place)
    }

    // MARK: Projection

    /// Orthographic projection. Returns the screen point and depth (> 0 means facing us).
    private func project(lat: Double, lon: Double, center: CGPoint, radius: CGFloat) -> (CGPoint, Double) {
        let φ = lat * .pi / 180, λ = (lon - motion.longitude) * .pi / 180, φ0 = motion.latitude * .pi / 180
        let x = cos(φ) * sin(λ)
        let y = cos(φ0) * sin(φ) - sin(φ0) * cos(φ) * cos(λ)
        let z = sin(φ0) * sin(φ) + cos(φ0) * cos(φ) * cos(λ)
        return (CGPoint(x: center.x + x * radius, y: center.y - y * radius), z)
    }

    private func nearestToCenter() -> Place? {
        var best: (Place, Double)?
        for place in Place.all {
            let (_, z) = project(lat: place.latitude, lon: place.longitude, center: .zero, radius: 1)
            if z > 0.94, z > (best?.1 ?? 0) { best = (place, z) }
        }
        return best?.0
    }

    private func hit(_ point: CGPoint, center: CGPoint, radius: CGFloat) -> Place? {
        Place.all
            .map { p -> (Place, CGPoint, Double) in
                let (s, z) = project(lat: p.latitude, lon: p.longitude, center: center, radius: radius)
                return (p, s, z)
            }
            .filter { $0.2 > 0.1 && hypot($0.1.x - point.x, $0.1.y - point.y) < 28 }
            .max { $0.2 < $1.2 }?.0
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        let sphere = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        // Atmosphere glow behind the globe.
        ctx.fill(Path(ellipseIn: sphere.insetBy(dx: -radius * 0.25, dy: -radius * 0.25)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0x3a5a8c).opacity(0.35), .clear]),
                                       center: center, startRadius: radius * 0.9, endRadius: radius * 1.25))
        // The sphere: lit from the upper left.
        ctx.fill(Path(ellipseIn: sphere),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0x1b2230), Color(hex: 0x0b0e14)]),
                                       center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4),
                                       startRadius: 0, endRadius: radius * 1.5))

        // Graticule as fine dots, fading toward the edge.
        for lat in stride(from: -60.0, through: 60.0, by: 30) {
            dottedLine(&ctx, points: stride(from: -180.0, to: 180.0, by: 3).map { (lat, $0) }, center: center, radius: radius)
        }
        for lon in stride(from: -180.0, to: 180.0, by: 30) {
            dottedLine(&ctx, points: stride(from: -80.0, through: 80.0, by: 3).map { ($0, lon) }, center: center, radius: radius)
        }

        // Land, as dots.
        for (lat, lon) in LandMask.points {
            let (p, z) = project(lat: Double(lat), lon: Double(lon), center: center, radius: radius)
            guard z > 0 else { continue }
            let r = 1.1 + 0.6 * z
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(0.10 + 0.32 * z)))
        }

        // Rim light.
        ctx.stroke(Path(ellipseIn: sphere), with: .color(.white.opacity(0.12)), lineWidth: 1)

        // Labels: the focused city always, then others nearest the viewer first,
        // skipping any that would collide with one already placed.
        var labeled: [CGPoint] = []
        var showLabel: Set<String> = []
        let byDepth = Place.all
            .map { ($0, project(lat: $0.latitude, lon: $0.longitude, center: center, radius: radius)) }
            .filter { $0.1.1 > 0.75 }
            .sorted { a, b in (a.0 == focused ? 2 : a.1.1) > (b.0 == focused ? 2 : b.1.1) }
        for (place, (p, _)) in byDepth where !labeled.contains(where: { abs($0.x - p.x) < 110 && abs($0.y - p.y) < 28 }) {
            labeled.append(p)
            showLabel.insert(place.name)
        }

        // Cities.
        for place in Place.all {
            let (p, z) = project(lat: place.latitude, lon: place.longitude, center: center, radius: radius)
            guard z > 0 else { continue }
            let isFocused = place == focused
            let isPlaying = place == mixer.escape?.place && mixer.mode == .escape
            let pulse = 1 + 0.15 * sin(time * 2 + place.longitude)
            let glow = (isFocused ? 30 : 16) * pulse * (0.5 + 0.5 * z)
            let color = place.accent.orb
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [color.opacity(0.75 * z), .clear]),
                                           center: p, startRadius: 0, endRadius: glow))
            let dot = isFocused ? 5.5 : 3.5
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
                     with: .color(.white.opacity(0.6 + 0.4 * z)))
            if isPlaying {
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)),
                           with: .color(.white.opacity(0.7 * z)), lineWidth: 1)
            }
        }

        // Labels last, so no city's glow or dot covers them; a dark shadow keeps them legible over land.
        var labels = ctx
        labels.addFilter(.shadow(color: .black.opacity(0.9), radius: 3))
        for place in Place.all where showLabel.contains(place.name) {
            let (p, z) = project(lat: place.latitude, lon: place.longitude, center: center, radius: radius)
            let isFocused = place == focused
            labels.draw(Text(place.title)
                            .font(Theme.mono(isFocused ? 12 : 10, isFocused ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(isFocused ? 0.95 : 0.55 * z)),
                        at: CGPoint(x: p.x, y: p.y + (isFocused ? 22 : 15)))
        }
    }

    private func dottedLine(_ ctx: inout GraphicsContext, points: [(Double, Double)], center: CGPoint, radius: CGFloat) {
        for (lat, lon) in points {
            let (p, z) = project(lat: lat, lon: lon, center: center, radius: radius)
            guard z > 0 else { continue }
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 0.6, y: p.y - 0.6, width: 1.2, height: 1.2)),
                     with: .color(.white.opacity(0.12 * z)))
        }
    }
}

// MARK: Card and list

/// The focused place: its live weather and what it sounds like, with a Listen button.
private struct PlaceCard: View {
    @Environment(Mixer.self) private var mixer
    let place: Place
    let listen: (Place) -> Void

    var body: some View {
        let c = mixer.placeConditions[place.name]
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(place.title).font(Theme.display(28)).tracking(-0.6)
                Text(c.map { "\(place.country) · \($0.temperature) · \($0.mixName)" } ?? place.country)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.mono)
                Text(place.signature.map(\.0.short).joined(separator: " · "))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Button { listen(place) } label: {
                Text("Listen")
                    .font(Theme.body(15, .medium))
                    .foregroundStyle(Theme.background)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(Capsule().fill(Theme.text))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Listen to \(place.title)")
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .animation(.smooth(duration: 0.25), value: place)
    }
}

/// Every place, by region, with its live weather.
private struct PlaceList: View {
    @Environment(Mixer.self) private var mixer
    let listen: (Place) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(Place.Region.allCases, id: \.self) { region in
                    Section {
                        ForEach(Place.all.filter { $0.region == region }) { place in
                            Button { listen(place) } label: { row(place) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        Text(region.rawValue.uppercased())
                            .font(Theme.mono(11, .medium))
                            .tracking(1.3)
                            .foregroundStyle(Theme.mono)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .background(Theme.background)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ place: Place) -> some View {
        let c = mixer.placeConditions[place.name]
        let current = place == mixer.escape?.place && mixer.mode == .escape
        return HStack(spacing: 14) {
            Circle()
                .fill(place.accent.orb)
                .frame(width: 10, height: 10)
                .shadow(color: place.accent.glow, radius: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.title).font(Theme.body(17))
                Text(place.signature.map(\.0.short).joined(separator: " · "))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.mono)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(c?.temperature ?? "–").font(Theme.mono(13))
                Text(c?.mixName ?? "").font(Theme.mono(10)).foregroundStyle(Theme.mono)
            }
            if current {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 12)).foregroundStyle(Theme.mono)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}
