import SwiftUI

/// Listening: the wheel, the halo and the scene's name, with the ones before and after beside it.
/// Swipe with two fingers or press ← → to travel, ↑ ↓ to turn the wheel, click the light for its
/// layers or drag it to turn it, click the name to search. Along the bottom, what's playing
/// (click it for its layers), the sleep timer and play.
struct MacListen: View {
    @Environment(Mixer.self) private var mixer
    @Environment(MacNavigation.self) private var navigation
    @State private var dragX: CGFloat = 0
    @FocusState private var focused: Bool
    @State private var hint: String?
    /// How many of the one-time hints have been shown.
    @AppStorage("macHintStep") private var hintStep = 0

    private static let hints = [
        "Swipe with two fingers, or press → to travel",
        "Click the light to tune it  ⌘E",
        "Click the name for the Library, ⌘K to search",
        "Drag the light to turn it",
        "↑ ↓ turn the wheel",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // What swiping goes through, as on the phone. (Outside on it, or ⇧⌘H, is your own weather.)
            ModeWheel()

            Carousel(dragX: $dragX, openMixer: { navigation.tuning.toggle() }, search: { navigation.tab = .library })
                .frame(minHeight: 340, maxHeight: .infinity)
                .overlay { TravelArrows() }

            VolumeLine()
                .frame(height: 40)
                .padding(.top, 6)

            HStack(spacing: 14) {
                LayersLink(orbs: mixer.byVolume) { navigation.tuning.toggle() }
                ResetTuning()
                TimerMenu()
                MacPlayButton()
            }
            .padding(.top, 14)
            .animation(.smooth, value: mixer.currentPlaceIsTweaked)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { mixer.requestTravel(forward: false); return .handled }
        .onKeyPress(.rightArrow) { mixer.requestTravel(forward: true); return .handled }
        .onKeyPress(.upArrow) { mixer.turnWheel(forward: false); return .handled }
        .onKeyPress(.downArrow) { mixer.turnWheel(forward: true); return .handled }
        .onAppear { focused = true }
        .overlay(alignment: .bottom) {
            ZStack {
                if let text = mixer.notice ?? hint { HintBubble(text: text) }
            }
            .padding(.bottom, 130)
            .animation(.smooth(duration: 0.3), value: mixer.notice)
        }
        .task { await runHints() }
        .haptic(.thud, trigger: mixer.shuffleCount)
    }

    /// Shows each hint once, the first times the window opens.
    private func runHints() async {
        // Not over the welcome: after it.
        while !UserDefaults.standard.bool(forKey: "onboarded") {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
        }
        while hintStep < Self.hints.count {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.5)) { hint = Self.hints[hintStep] }
            hintStep += 1
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.smooth(duration: 0.5)) { hint = nil }
        }
    }
}

/// For a mouse: faint arrows at the edges of the halo while the pointer is over it, to travel
/// back or on. (A trackpad swipes; the keyboard has ← →.)
private struct TravelArrows: View {
    @Environment(Mixer.self) private var mixer
    @State private var hovering = false

    var body: some View {
        HStack {
            arrow("chevron.left", label: "Go back", enabled: mixer.previous != nil) { mixer.requestTravel(forward: false) }
            Spacer()
            arrow("chevron.right", label: "Travel somewhere new", enabled: mixer.next != nil) { mixer.requestTravel(forward: true) }
        }
        .padding(.horizontal, -18)
        .padding(.bottom, 80)   // level with the halo, above the title
        .opacity(hovering ? 1 : 0)
        .animation(.smooth(duration: 0.25), value: hovering)
        .onContinuousHover { phase in
            if case .active = phase { hovering = true } else { hovering = false }
        }
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text.opacity(0.75))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// What's playing, by its sounds' names: click for its layers.
private struct LayersLink: View {
    let orbs: [Orb]
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LayerStrip(orbs: orbs, color: hovering ? Theme.secondary : Theme.muted)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Tune  ⌘E")
        .accessibilityHint("Opens Tune")
    }
}

/// The sleep timer beside play: a moon when there's none, otherwise how long it's set for.
struct TimerMenu: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        Menu {
            Picker("Sleep timer", selection: Binding(get: { mixer.timer }, set: { mixer.setTimer($0) })) {
                ForEach(Mixer.Timer.allCases, id: \.self) { t in
                    Text(t == .off ? "No timer" : "Stop after \(t.label)").tag(t)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Group {
                if mixer.timer == .off {
                    Image(systemName: "moon").font(.system(size: 12))
                } else {
                    Text(mixer.timer.label).font(Theme.label(11))
                }
            }
            .foregroundStyle(Theme.muted)
            .padding(6)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sleep timer")
        .haptic(.tick, trigger: mixer.timer)
    }
}

/// A quiet ring rather than a big disc, so the scene stays the focus. Right-click for a timer.
private struct MacPlayButton: View {
    @Environment(Mixer.self) private var mixer
    @State private var hovering = false

    var body: some View {
        Button { mixer.togglePlayback() } label: {
            ZStack {
                Circle().strokeBorder(Theme.text.opacity(hovering ? 1 : 0.8), lineWidth: 1.5)
                if mixer.isPlaying {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 1.5).frame(width: 4, height: 17)
                        RoundedRectangle(cornerRadius: 1.5).frame(width: 4, height: 17)
                    }
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .offset(x: 1.5)
                }
            }
            .foregroundStyle(Theme.text)
            .frame(width: 56, height: 56)
            .background(Circle().fill(.white.opacity(hovering ? 0.06 : 0)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
        .help(mixer.isPlaying ? "Pause  (Space)" : "Play  (Space)")
        .contextMenu {
            Picker("Sleep timer", selection: Binding(get: { mixer.timer }, set: { mixer.setTimer($0) })) {
                ForEach(Mixer.Timer.allCases, id: \.self) { t in
                    Text(t == .off ? "No timer" : "Stop after \(t.label)").tag(t)
                }
            }
            .pickerStyle(.inline)
        }
        .haptic(.thud, trigger: mixer.isPlaying)
        .accessibilityLabel(mixer.isPlaying ? "Pause" : "Play")
    }
}
