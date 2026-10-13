import SwiftUI

#if os(iOS)
/// Layers: the shape of what's playing, washed in the colors of the mix. Each sound is a bulge in
/// the glass, as far out as it's loud: pull one out to hear more of it, push it in to let it go,
/// and drag around it to turn the shape. The sections below add a sound or take it away.
/// (On the Mac, `MacLayers` shows the same parts.)
struct MixerView: View {
    @Environment(Mixer.self) private var mixer
    @State private var saving = false
    @State private var resetting = false

    var body: some View {
        VStack(spacing: 0) {
            ShapeField()

            Text(mixer.currentPlaceIsTweaked
                 ? "Your changes to \(mixer.currentPlaceName) are kept"
                 : "Pull a sound out to hear more · drag to turn")
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

/// The shape of the sound, large: the glass form from the home screen with a handle at the tip of
/// each sound's bulge. Pull one out to hear more of it, push it all the way in to let it go, and
/// drag anywhere else to turn the shape.
struct ShapeField: View {
    @Environment(Mixer.self) private var mixer
    // It opens turned just as the home screen's form is, so it's the same shape, closer.
    @State private var yaw = SculptureSpin.home.yaw
    @State private var pitch = SoundForm.pitch + SculptureSpin.home.tilt
    @State private var turnStart: (yaw: Double, pitch: Double)?

    /// How much of the view the shape is fitted to (see `SculptureCamera.extent`).
    static let extent = 0.72

    var body: some View {
        GeometryReader { proxy in
            let camera = SculptureCamera(yaw: yaw, pitch: pitch, size: proxy.size, extent: Self.extent)
            let bodies = SculptureStyle.shape.bodies(of: mixer.orbs, at: 0)
            let middle = camera.project(0, 0, 0).point
            ZStack {
                SculptureView(orbs: mixer.orbs, style: .shape, yaw: yaw, pitch: pitch, extent: Self.extent, animated: false)
                // Faint spokes from the middle out to each sound, the lines its handle moves along.
                Path { path in
                    for part in bodies {
                        let reach = SculptureStyle.tipDistance(volume: 1)
                        let far = camera.project(part.direction.x * reach, part.direction.y * reach, part.direction.z * reach).point
                        path.move(to: middle)
                        path.addLine(to: far)
                    }
                }
                .stroke(Theme.text.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .allowsHitTesting(false)
                ForEach(bodies) { part in
                    SoundHandle(part: part, camera: camera)
                }
            }
            .coordinateSpace(name: "shape")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { g in
                        if turnStart == nil { turnStart = (yaw, pitch) }
                        guard let start = turnStart else { return }
                        yaw = start.yaw + g.translation.width * 0.008
                        pitch = min(1.4, max(-0.2, start.pitch + g.translation.height * 0.005))
                    }
                    .onEnded { _ in turnStart = nil }
            )
        }
        // A tick every eighth of a turn.
        .sensoryFeedback(.selection, trigger: Int((yaw / (.pi / 8)).rounded(.down)))
        .sensoryFeedback(.impact(weight: .light), trigger: mixer.orbs.count)
        // And the home screen's form carries on from however you've turned it here.
        .onDisappear { SculptureSpin.home.hold(yaw: yaw, tilt: pitch - SoundForm.pitch) }
    }
}

/// A sound in the shape: a handle at the tip of its bulge, named just beyond it. Drag it out along
/// its spoke to make the sound louder, in to make it quieter, and right into the middle to let it go.
private struct SoundHandle: View {
    @Environment(Mixer.self) private var mixer
    let part: SculptureBody
    let camera: SculptureCamera
    @State private var dragging = false
    @State private var removing = false

    var body: some View {
        let tip = part.tip
        let spot = camera.project(tip.x, tip.y, tip.z)
        let middle = camera.project(0, 0, 0).point
        // The spoke on screen: which way is out, and how many points a unit along it takes.
        let reach = camera.project(part.direction.x, part.direction.y, part.direction.z).point
        let along = CGVector(dx: reach.x - middle.x, dy: reach.y - middle.y)
        let unit = max(1, hypot(along.dx, along.dy))
        let out = CGVector(dx: along.dx / unit, dy: along.dy / unit)
        let pct = Int((part.orb.volume * 100).rounded())

        Circle()
            .fill(part.orb.kind.orb)
            .overlay(Circle().strokeBorder(Theme.text, lineWidth: 2))
            .frame(width: 15, height: 15)
            .shadow(color: part.orb.kind.glow.opacity(0.9), radius: dragging ? 9 : 5)
            .scaleEffect(dragging ? 1.3 : 1)
            .opacity(removing ? 0.4 : 1)
            .frame(width: 44, height: 44)
            .overlay {
                Text(removing ? "Release to remove" : dragging ? "\(part.orb.kind.short) \(pct)" : part.orb.kind.short)
                    .font(Theme.label(10.5, .medium))
                    .foregroundStyle(removing ? Theme.text : Theme.orbLabel)
                    .shadow(color: .black.opacity(0.75), radius: 3)
                    .fixedSize()
                    .offset(x: out.dx * 34, y: out.dy * 26 + (out.dy > -0.3 ? 4 : -4))
                    .allowsHitTesting(false)
            }
            .contentShape(Circle())
            .position(spot.point)
            .zIndex(dragging ? 1000 : -spot.depth)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("shape"))
                    .onChanged { g in
                        dragging = true
                        // How far out along the spoke the finger is, in the shape's own units.
                        let t = ((g.location.x - middle.x) * out.dx + (g.location.y - middle.y) * out.dy) / unit
                        removing = t < 0.17
                        mixer.setVolume(part.orb.id, to: max(0.03, SculptureStyle.volume(atTip: t)))
                    }
                    .onEnded { _ in
                        if removing { withAnimation(.snappy) { mixer.remove(part.orb.id) } }
                        dragging = false
                        removing = false
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { mixer.remove(part.orb.id) }
            }
            .animation(.snappy(duration: 0.2), value: dragging)
            .animation(.snappy(duration: 0.18), value: removing)
            // A soft tap on pickup, a tick per 10% of volume, and a firm snap when it's ready to remove.
            .sensoryFeedback(.impact(flexibility: .soft), trigger: dragging) { _, isDragging in isDragging }
            .sensoryFeedback(.selection, trigger: pct / 10) { _, _ in dragging }
            .sensoryFeedback(.impact(weight: .heavy), trigger: removing) { _, now in now }
            .accessibilityElement()
            .accessibilityLabel(part.orb.kind.name)
            .accessibilityValue("\(pct) percent")
            .accessibilityAdjustableAction { direction in
                mixer.adjustVolume(part.orb.id, by: direction == .increment ? 0.1 : -0.1)
            }
            .accessibilityAction(named: "Remove") { mixer.remove(part.orb.id) }
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
