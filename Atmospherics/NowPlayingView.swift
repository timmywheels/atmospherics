import SwiftUI

/// Home screen: a breathing halo of the current sounds, the mix name, and the main controls.
struct NowPlayingView: View {
    @Environment(Mixer.self) private var mixer
    @State private var showLibrary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ATMOSPHERICS")
                Spacer()
                Text("\(mixer.weather.place) \(mixer.weather.temp)")
            }
            .font(Theme.mono(11, .medium))
            .tracking(1.3)
            .foregroundStyle(Theme.mono)

            Halo(orbs: mixer.byVolume)
                .frame(height: 380)
                .padding(.top, 20)

            Button { showLibrary = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(mixer.title)
                        .font(Theme.display(44))
                        .tracking(-1.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.mono)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the library")

            Text(mixer.weather.line)
                .font(Theme.body(15))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 10)

            Text(mixer.layersLine)
                .font(Theme.mono(11))
                .lineSpacing(4)
                .foregroundStyle(Theme.mono)
                .padding(.top, 14)

            ModeToggle()
                .padding(.top, 28)

            Spacer(minLength: 16)

            VStack(spacing: 14) {
                HStack {
                    Button { showLibrary = true } label: {
                        Text("Library ↑")   // opens as a sheet, so it points up
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }

                    PlayButton()

                    NavigationLink(value: Route.mixer) {
                        Text("Mixer →")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                }

                Button { mixer.cycleTimer() } label: {
                    Text(mixer.timer == .off ? "Timer off" : "Timer · \(mixer.timer.label)")
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Sleep timer, \(mixer.timer.label). Tap to change.")
            }
            .font(Theme.mono(12))
            .foregroundStyle(Theme.mono)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .sheet(isPresented: $showLibrary) {
            LibraryView()
        }
    }
}

enum Route: Hashable { case mixer }

/// Soft blurred lights, one per sound. Louder sounds are bigger and sit nearer the center.
private struct Halo: View {
    let orbs: [Orb]

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                ForEach(Array(orbs.enumerated()), id: \.element.id) { i, orb in
                    let angle = Double(i) * 2.1 + 0.4
                    let distance = (1 - orb.volume) * 70
                    // Slightly smaller and softer than the CSS values: SwiftUI's blur
                    // spreads less, so the same numbers render bigger and harsher.
                    let size = (90 + orb.volume * 200) * 0.85
                    Breathing(period: 7 + Double(i) * 1.7) {
                        Circle()
                            .fill(orb.kind.halo.opacity(0.85))
                            .frame(width: size, height: size)
                            .blur(radius: 22)
                    }
                    .blendMode(.screen)
                    .position(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                    .animation(.smooth(duration: 0.6), value: orb.volume)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .position(center)
            }
            .compositingGroup()
        }
        .accessibilityHidden(true)
    }
}

/// Slowly scales its content between 1 and 1.08, like the design's `breathe` keyframes.
private struct Breathing<Content: View>: View {
    let period: Double
    @ViewBuilder let content: Content
    @State private var expanded = false

    var body: some View {
        content
            .scaleEffect(expanded ? 1.08 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) {
                    expanded = true
                }
            }
    }
}

/// "Match outside / Escape outside" segmented pill.
struct ModeToggle: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        HStack(spacing: 0) {
            segment("Match outside", .match)
            segment("Escape outside", .escape)
        }
        .padding(4)
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func segment(_ label: String, _ mode: Mode) -> some View {
        let selected = mixer.mode == mode
        return Button {
            withAnimation(.smooth(duration: 0.35)) { mixer.setMode(mode) }
        } label: {
            Text(label)
                .font(Theme.body(14, .medium))
                .foregroundStyle(selected ? Theme.background : Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(selected ? Theme.text : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PlayButton: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        Button { mixer.togglePlayback() } label: {
            ZStack {
                Circle().fill(Theme.text)
                if mixer.isPlaying {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).frame(width: 5, height: 20)
                        RoundedRectangle(cornerRadius: 2).frame(width: 5, height: 20)
                    }
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))
                        .offset(x: 2)
                }
            }
            .foregroundStyle(Theme.background)
            .frame(width: 68, height: 68)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mixer.isPlaying ? "Pause" : "Play")
    }
}
