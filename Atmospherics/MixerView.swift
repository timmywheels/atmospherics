import SwiftUI

#if os(iOS)
/// Layers: every sound that's playing, each with its own level to set (`SoundList`), washed in the
/// colors of the mix, and below, every sound to add or take away (`SoundSections`). (On the Mac,
/// `MacLayers` shows the same parts.)
struct MixerView: View {
    @Environment(Mixer.self) private var mixer
    @State private var saving = false
    @State private var resetting = false

    var body: some View {
        VStack(spacing: 0) {
            SoundList()

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

/// Every sound that's playing, a layer each in the order they came in, filled in its color as far
/// across as it's loud: tap or drag across one to set its level, or hold it to take it away. Last,
/// an empty layer brings in a sound at random. (The sounds to pick from are below, in
/// `SoundSections`.) All in the monospace.
struct SoundList: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mixer.currentPlaceIsTweaked ? "Your changes to \(mixer.currentPlaceName) are kept"
                 : "Tap or drag across a layer to set its level.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
            GeometryReader { proxy in
                // As tall as there's room for, down to a fingertip's height with a lot playing.
                let height = min(84, max(44, proxy.size.height / CGFloat(mixer.orbs.count + 1)))
                VStack(spacing: 0) {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    ForEach(mixer.orbs) { orb in
                        LevelRow(orb: orb, height: height)
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    RandomLayer(height: height)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }
            .clipped()
        }
        .animation(.snappy, value: mixer.orbs.map(\.id))
    }
}

/// One sound as a layer: filled in its color from the left as far as it's loud, its name large and
/// its level small. Tap anywhere across it to set the level
/// there (it glides over), or drag across to slide it.
private struct LevelRow: View {
    @Environment(Mixer.self) private var mixer
    let orb: Orb
    let height: CGFloat
    @State private var sliding = false
    @State private var taps = 0

    private var percent: Int { Int((orb.volume * 100).rounded()) }

    var body: some View {
        GeometryReader { proxy in
            bar(width: proxy.size.width)
                .contentShape(Rectangle())
                .onTapGesture { location in set(location.x, of: proxy.size.width, gliding: true) }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { g in
                            sliding = true
                            set(g.location.x, of: proxy.size.width, gliding: false)
                        }
                        .onEnded { _ in sliding = false }
                )
        }
        .frame(height: height)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.snappy) { mixer.remove(orb.id) }
            } label: { Label("Remove \(orb.kind.name)", systemImage: "xmark") }
        }
        // A tap where you set it, and a tick per 10% as it slides.
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .sensoryFeedback(.selection, trigger: percent / 10) { _, _ in sliding }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(orb.kind.name)
        .accessibilityValue("\(percent) percent")
        .accessibilityAdjustableAction { direction in
            mixer.adjustVolume(orb.id, by: direction == .increment ? 0.1 : -0.1)
        }
        .accessibilityAction(named: "Remove") { mixer.remove(orb.id) }
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
                Text("\(percent)%")
                    .font(Theme.caps(11))
                    .foregroundStyle(Theme.text.opacity(0.85))
            }
            .padding(.horizontal, 24)
            .shadow(color: .black.opacity(0.25), radius: 6)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// The last layer, empty: tap it to bring in a sound that isn't playing yet, picked at random.
private struct RandomLayer: View {
    @Environment(Mixer.self) private var mixer
    let height: CGFloat

    var body: some View {
        let waiting = SoundKind.available.filter { kind in !mixer.orbs.contains { $0.kind == kind } }
        Button {
            guard let kind = waiting.randomElement() else { return }
            Haptics.tap(.light)
            withAnimation(.snappy) { mixer.add(kind) }
        } label: {
            Text("+ Random")
                .font(Theme.display(height > 64 ? 32 : 24))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: height)
        .disabled(waiting.isEmpty)
        .accessibilityLabel("Add a random sound")
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
