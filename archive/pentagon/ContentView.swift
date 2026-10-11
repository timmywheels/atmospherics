import SwiftUI

struct ContentView: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        ZStack {
            Backdrop().ignoresSafeArea()

            VStack(spacing: 16) {
                header
                Spacer(minLength: 0)
                SoundField()
                Spacer(minLength: 0)

                SpectrumView()
                    .frame(height: 64)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .glassCard()

                PlayButton()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .preferredColorScheme(.dark)
        .alert("Audio error", isPresented: .constant(mixer.errorMessage != nil)) {
            Button("OK") { mixer.errorMessage = nil }
        } message: {
            Text(mixer.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ATMOSPHERICS")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(5)
                .foregroundStyle(.secondary)
            Text(mixer.mixTitle)
                .font(.system(size: 32, weight: .light, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.white, mixer.overallColor], startPoint: .leading, endPoint: .trailing)
                )
                .contentTransition(.interpolate)
                .animation(.smooth(duration: 0.4), value: mixer.mixTitle)
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hint: String {
        switch mixer.dots.count {
        case 1: "Drag the dot to blend · tap to add another"
        case Mixer.maxDots: "Drag a dot off the edge to remove it"
        default: "Tap to add a dot · drag one off to remove"
        }
    }
}

/// Slow nebula behind everything, tinted by the mix.
private struct Backdrop: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1 / 20, paused: !mixer.isPlaying)) { timeline in
                Rectangle().colorEffect(ShaderLibrary.backdrop(
                    .float2(proxy.size),
                    .float(timeline.date.timeIntervalSince(appStart)),
                    .color(mixer.overallColor)
                ))
            }
        }
    }
}

private struct PlayButton: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        Button {
            mixer.togglePlayback()
        } label: {
            Image(systemName: mixer.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .glassCircle(tint: mixer.isPlaying ? mixer.overallColor : nil)
        .shadow(color: mixer.overallColor.opacity(mixer.isPlaying ? 0.5 : 0), radius: 20)
        .accessibilityLabel(mixer.isPlaying ? "Pause" : "Play")
    }
}

// MARK: Liquid Glass, with a frosted fallback before iOS 26

private extension View {
    @ViewBuilder func glassCard() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 26))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    @ViewBuilder func glassCircle(tint: Color?) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(tint?.opacity(0.35)).interactive(), in: .circle)
        } else {
            background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().fill((tint ?? .clear).opacity(0.2)))
        }
    }
}
