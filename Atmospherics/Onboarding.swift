import SwiftUI

/// The first time the app opens: a soundscape putting itself together, a sound and a light at a
/// time (rain, a breeze in the eaves, a far harbor bell), until it's whole and has a name, "A
/// harbor, at dusk". Then the question, "Where would you like to go?", with somewhere to type and
/// four ways to begin: right here (the only one that asks where you are), somewhere far, somewhere
/// to focus, somewhere imagined. Choosing one plays it and the welcome is done. A tap, or Reduce
/// Motion, goes straight to the question. About ten seconds.
struct Onboarding: View {
    @Environment(Mixer.self) private var mixer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let done: () -> Void

    /// 0 the opening line, 1 to 3 a sound each, 4 whole and named, 5 the question.
    @State private var beat = -1
    @State private var pills: [SoundKind] = []
    @State private var query = ""
    @State private var imagining = false
    @State private var notUnderstood = false
    @State private var running: Task<Void, Never>?
    @FocusState private var typing: Bool

    private static let harbor: [(SoundKind, Double, Double)] = [
        (.lightRain, 0.62, 1.2), (.breeze, 0.48, 3.6), (.buoy, 0.4, 5.4),
    ]

    var body: some View {
        ZStack {
            SceneWash(orbs: mixer.byVolume)
                .opacity(beat >= 1 ? 1 : 0)
                .background(Theme.background)
                .ignoresSafeArea()
                .animation(.smooth(duration: 1.6), value: beat >= 1)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    Text("Every place has a sound.")
                        .font(Theme.display(34))
                        .multilineTextAlignment(.center)
                        .opacity(beat == 0 ? 1 : 0)
                    SoundForm(orbs: mixer.byVolume)
                        .frame(width: 300, height: 300)
                        .opacity(beat >= 1 ? 1 : 0)
                        .scaleEffect(beat >= 4 ? 1 : 0.86)
                }
                .frame(height: 320)

                // The sounds as they come, and the name once it's whole.
                ZStack {
                    HStack(spacing: 14) {
                        ForEach(pills, id: \.self) { kind in
                            HStack(spacing: 6) {
                                Circle().fill(kind.orb).frame(width: 7, height: 7)
                                Text(kind.short).font(Theme.label(13))
                            }
                            .foregroundStyle(Theme.secondary)
                            .transition(.opacity.combined(with: .offset(y: -8)))
                        }
                    }
                    .opacity(beat >= 1 && beat < 5 ? 1 : 0)
                }
                .frame(height: 28)

                Text("A harbor, at dusk.")
                    .font(Theme.display(38))
                    .opacity(beat == 4 ? 1 : 0)
                    .padding(.top, 10)
                    .frame(height: beat >= 5 ? 0 : nil)
                    .clipped()

                if beat >= 5 { question.transition(.opacity.combined(with: .offset(y: 16))) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 520)
        }
        .foregroundStyle(Theme.text)
        .contentShape(Rectangle())
        .onTapGesture { if beat < 5 { toQuestion() } }
        .animation(.smooth(duration: 0.9), value: beat)
        .animation(.smooth(duration: 0.6), value: pills)
        .task { start() }
        .onDisappear { running?.cancel() }
        .accessibilityAction(named: "Skip") { toQuestion() }
    }

    // MARK: The harbor, put together

    private func start() {
        mixer.beginWelcome()
        if reduceMotion { return toQuestion() }
        running = Task { @MainActor in
            beat = 0
            try? await Task.sleep(for: .seconds(1.8))
            for (i, (kind, level, angle)) in Self.harbor.enumerated() {
                guard !Task.isCancelled else { return }
                beat = i + 1
                mixer.welcome(kind, level: level, angle: angle)
                pills.append(kind)
                Haptics.play(.soft)
                try? await Task.sleep(for: .seconds(1.6))
            }
            guard !Task.isCancelled else { return }
            beat = 4
            Haptics.play(.detent)
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            beat = 5
        }
    }

    /// Straight to the question, the harbor whole.
    private func toQuestion() {
        running?.cancel()
        for (kind, level, angle) in Self.harbor where !pills.contains(kind) {
            mixer.welcome(kind, level: level, angle: angle)
            pills.append(kind)
        }
        beat = 5
    }

    // MARK: The question

    private var question: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Where would you like to go?")
                .font(Theme.display(36))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if imagining {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                }
                TextField("", text: $query, prompt: Text("a rainy night in Tokyo, a cabin in the snow…").foregroundStyle(Theme.muted))
                    .textFieldStyle(.plain)
                    .font(Theme.label(15))
                    .focused($typing)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(imagine)
                    .onChange(of: query) { _, _ in notUnderstood = false }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))

            if notUnderstood {
                Text("Try a place and some weather, like “a cabin in the snow”.")
                    .font(Theme.label(11))
                    .foregroundStyle(Theme.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                choice("Right here, as it is now", "To hear the weather where you are", 0) {
                    mixer.playHere()
                }
                choice("Somewhere far", "A real place, in its weather now", 1) {
                    if let p = farAway() { mixer.revisit(.place(p)) }
                }
                choice("Somewhere to focus", "Noise and rain that research supports", 2) {
                    if let p = Preset.all.first(where: { $0.tag == .focus && $0.evidence == .strong }) { mixer.load(p) }
                }
                choice("Somewhere imagined", "A scene, in weather of its own", 3) {
                    mixer.revisit(.scene(Atmosphere.curated.randomElement() ?? Atmosphere.curated[0]))
                }
            }
        }
        .padding(.top, 8)
    }

    @State private var shown = 0

    private func choice(_ title: String, _ line: String, _ i: Int, go: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.thud)
            go()
            finish()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.label(15, .medium))
                Text(line).font(Theme.label(11)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(shown > i ? 1 : 0)
        .offset(y: shown > i ? 0 : 8)
        .task {
            // One after another, 80 ms apart.
            try? await Task.sleep(for: .milliseconds(200 + 80 * i))
            withAnimation(.smooth(duration: 0.4)) { shown = max(shown, i + 1) }
        }
    }

    /// A real place where it's night and not clear now, if the weather's in; any other way, one far.
    private func farAway() -> Place? {
        let far = Place.all.filter { p in
            guard let c = mixer.placeConditions[p.name] else { return false }
            return !c.isDay && (c.isRaining || c.isSnow || c.isFog || c.windKMH > 20)
        }
        return far.randomElement() ?? Place.all.randomElement()
    }

    private func imagine() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !imagining else { return }
        imagining = true
        Task { @MainActor in
            let vibe = await Vibe.read(text, draft: Atmosphere.curated[0])
            imagining = false
            guard let vibe else { notUnderstood = true; return }
            Vibe.remember(text)
            Haptics.play(.thud)
            mixer.go(to: vibe)
            finish()
        }
    }

    private func finish() {
        running?.cancel()
        done()
    }
}
