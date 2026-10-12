import SwiftUI

/// Layers: the whole screen is the field, washed in the colors of the mix (after the Breath
/// direction). You're at the center; drag a light closer to hear more of it, out past the rim
/// to let it go. The pills along the bottom add a sound or take it away.
struct MixerView: View {
    @Environment(Mixer.self) private var mixer
    @State private var saving = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let side = min(proxy.size.width - 20, proxy.size.height - 20)
                ZStack {
                    // A crosshair across the whole surface, through you.
                    Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
                    Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
                    FieldView(size: side)
                        .frame(width: side, height: side)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }

            Text(mixer.currentPlaceIsTweaked
                 ? "Your changes to \(mixer.currentPlaceName) are kept"
                 : "Closer is louder · drag past the rim to remove")
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.mono)
                .padding(.bottom, 14)

            SoundPills()
                .padding(.bottom, 10)
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

/// The round field: the rim is where a sound falls silent, and you're at the center.
private struct FieldView: View {
    @Environment(Mixer.self) private var mixer
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
            Circle().strokeBorder(.white.opacity(0.05), lineWidth: 1).padding(size / 6)
            Circle().strokeBorder(.white.opacity(0.05), lineWidth: 1).padding(size / 3)
            Circle().strokeBorder(Theme.text.opacity(0.75), lineWidth: 1.2).frame(width: 46, height: 46)
            Circle().fill(Theme.text).frame(width: 6, height: 6)
            Text("you")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.mono)
                .offset(y: 38)

            ForEach(mixer.orbs) { orb in
                OrbView(orb: orb, fieldSize: size)
            }
        }
        .coordinateSpace(name: "field")
        .sensoryFeedback(.impact(weight: .light), trigger: mixer.orbs.count)
    }
}

/// One sound: a soft light in its color with a bright core, bigger the closer it is.
private struct OrbView: View {
    @Environment(Mixer.self) private var mixer
    let orb: Orb
    let fieldSize: CGFloat
    @State private var dragging = false
    /// Where the finger is, in field units, while it's dragged past the rim.
    @State private var outside: CGPoint?

    /// Past this distance from center (the rim is 0.5), letting go removes the sound.
    private static let removeDistance = 0.68

    private var removing: Bool {
        guard let p = outside else { return false }
        return hypot(p.x - 0.5, p.y - 0.5) > Self.removeDistance
    }

    var body: some View {
        let v = orb.volume
        let glow = 44 + v * 76
        let core = 9 + v * 7
        let pct = Int((v * 100).rounded())
        let at = outside ?? CGPoint(x: orb.x, y: orb.y)

        ZStack {
            Circle()
                .fill((removing ? Theme.mono : orb.kind.halo).opacity(removing ? 0.4 : 0.9))
                .frame(width: glow, height: glow)
                .blur(radius: glow * 0.22)
                .blendMode(.screen)
            Circle()
                .fill(removing ? Theme.mono : orb.kind.orb)
                .frame(width: core, height: core)
                .shadow(color: orb.kind.glow, radius: removing ? 0 : 6)
            if removing {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.background)
            }
        }
        .scaleEffect(removing ? 0.8 : dragging ? 1.1 : 1)
        .frame(width: 56, height: 56)   // a comfortable touch target, whatever the light's size
        .overlay {
            // The name sits just under the light's core.
            Text(removing ? "Release to remove"
                 : outside != nil ? "Drag further to remove"
                 : dragging ? "\(orb.kind.short) \(pct)" : orb.kind.short)
                .font(Theme.mono(10, .medium))
                .foregroundStyle(removing ? Theme.text : Theme.orbLabel)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .fixedSize()
                .offset(y: core / 2 + 13)
                .allowsHitTesting(false)
        }
        .contentShape(Circle())
        .position(x: at.x * fieldSize, y: at.y * fieldSize)
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("field"))
                .onChanged { g in
                    dragging = true
                    let p = CGPoint(x: g.location.x / fieldSize, y: g.location.y / fieldSize)
                    // Inside the circle the light moves the sound; past the rim it follows
                    // the finger out (the sound sits silent at the rim) so it can be thrown away.
                    outside = hypot(p.x - 0.5, p.y - 0.5) > 0.5 ? p : nil
                    mixer.move(orb.id, toX: p.x, y: p.y)
                }
                .onEnded { _ in
                    if removing {
                        withAnimation(.snappy) { mixer.remove(orb.id) }
                    } else {
                        withAnimation(.spring(duration: 0.35, bounce: 0.35)) { outside = nil }
                    }
                    dragging = false
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
        .zIndex(dragging ? 1 : 0)
        .accessibilityElement()
        .accessibilityLabel(orb.kind.name)
        .accessibilityValue("\(pct) percent")
        .accessibilityAdjustableAction { direction in
            mixer.adjustVolume(orb.id, by: direction == .increment ? 0.1 : -0.1)
        }
        .accessibilityAction(named: "Remove") { mixer.remove(orb.id) }
    }
}

/// Every sound as a pill, lit while it's in the field: tap to add it or take it away.
/// What's playing comes first, then this place's own sounds, then everything else.
private struct SoundPills: View {
    @Environment(Mixer.self) private var mixer

    private var ordered: (kinds: [SoundKind], playing: Set<SoundKind>) {
        let playing = mixer.byVolume.map(\.kind)
        let rest = SoundKind.Category.allCases.flatMap { c in SoundKind.available.filter { $0.category == c } }
        var seen = Set<SoundKind>()
        return ((playing + mixer.currentCast + rest).filter { seen.insert($0).inserted }, Set(playing))
    }

    var body: some View {
        let (kinds, playing) = ordered
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
