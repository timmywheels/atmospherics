import SwiftUI

/// Home screen: a breathing halo of the current sounds, the mix name, and the main controls.
struct NowPlayingView: View {
    @Environment(Mixer.self) private var mixer
    @State private var showLibrary = false
    @State private var showGlobe = false
    @State private var swipe: CGFloat = 0
    @State private var pastThreshold = false
    @AppStorage("hasSwiped") private var hasSwiped = false

    private let swipeThreshold: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ATMOSPHERICS")
                Spacer()
                Button { showGlobe = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                        Text("\(mixer.weather.place) \(mixer.weather.temp)")
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("World. \(mixer.weather.place)")
            }
            .font(Theme.mono(11, .medium))
            .tracking(1.3)
            .foregroundStyle(Theme.mono)

            Halo(orbs: mixer.byVolume)
                .frame(minHeight: 300, maxHeight: .infinity)
                // Leans with the finger (with resistance) and softens, rather than flying away.
                .offset(x: swipe)
                .scaleEffect(1 - min(abs(swipe), 60) / 600)
                .blur(radius: min(abs(swipe), 60) / 12)
                .contentShape(Rectangle())
                .gesture(travelSwipe)
                .overlay(alignment: .bottom) {
                    if !hasSwiped {
                        Text("← swipe to travel →")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.mono.opacity(0.7))
                            .transition(.opacity)
                    }
                }
                .accessibilityAction(named: "Travel somewhere random") { mixer.shuffle() }

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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 10)

            // Always two lines tall, so places with more or fewer sounds don't shift the layout.
            Text(mixer.layersLine)
                .font(Theme.mono(11))
                .lineSpacing(4)
                .foregroundStyle(Theme.mono)
                .lineLimit(2, reservesSpace: true)
                .padding(.top, 14)

            // Away: a quiet way home. At home but edited: a way back to following the weather.
            // A fixed-height slot: the line fades in and out without moving anything.
            ZStack(alignment: .leading) {
                Text(" ").hidden()
                if mixer.mode == .escape {
                    Button { withAnimation(.smooth(duration: 0.35)) { mixer.goHome() } } label: {
                        Text("← Back to \(mixer.homeName)")
                    }
                } else if mixer.following[.match] != true {
                    Button { mixer.followWeatherAgain() } label: {
                        Text("↺ Follow the weather")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(Theme.mono(12))
            .foregroundStyle(Theme.text.opacity(0.8))
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .padding(.top, 14)
            .sensoryFeedback(.selection, trigger: mixer.mode)

            Waveform()
                .frame(height: 40)
                .padding(.top, 6)

            Spacer().frame(height: 18)

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
                .sensoryFeedback(.selection, trigger: mixer.timer)
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
        .fullScreenCover(isPresented: $showGlobe) {
            GlobeView()
        }
        // A soft tick when the swipe is far enough to count, a firmer one when it lands.
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: pastThreshold) { _, now in now }
        .sensoryFeedback(.impact(weight: .medium), trigger: mixer.shuffleCount)
    }

    /// Swipe the halo sideways to jump to a random place.
    private var travelSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { g in
                guard abs(g.translation.width) > abs(g.translation.height) else { return }
                // Rubber-band: follows the finger at first, then resists.
                let x = g.translation.width
                swipe = 60 * tanh(x / 160)
                pastThreshold = abs(x) > swipeThreshold
            }
            .onEnded { g in
                let travel = abs(g.translation.width) > swipeThreshold && abs(g.translation.width) > abs(g.translation.height)
                if travel {
                    mixer.shuffle()
                    withAnimation { hasSwiped = true }
                }
                // Settle back gently; the colors melt into the new place as the sound crossfades.
                withAnimation(.smooth(duration: 0.9)) { swipe = 0 }
                pastThreshold = false
            }
    }
}

enum Route: Hashable { case mixer }

/// Soft blurred lights, one per sound. Louder sounds are bigger and sit nearer the center.
/// Each light wanders slowly on its own path, and the whole halo drifts, so it feels alive.
struct Halo: View {
    let orbs: [Orb]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash: Double = 0
    @State private var seenStrikes: Int32 = 0

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                // Whole-halo drift: a slow figure-eight a few points across.
                let drift = CGPoint(x: sin(t * 0.07) * 12, y: sin(t * 0.11) * 8)
                ZStack {
                    ForEach(Array(orbs.enumerated()), id: \.element.id) { i, orb in
                        // A fixed spot per sound, so lights grow and shrink instead of swapping places.
                        let slot = Double(SoundKind.allCases.firstIndex(of: orb.kind) ?? i)
                        let angle = slot * 2.399 + 0.4
                        let distance = (1 - orb.volume) * 70
                        // Slightly smaller and softer than the CSS values: SwiftUI's blur
                        // spreads less, so the same numbers render bigger and harsher.
                        let size = (90 + orb.volume * 200) * 0.85
                        let phase = slot * 1.9
                        let wander = CGPoint(x: sin(t * 0.13 + phase) * 16, y: cos(t * 0.1 + phase * 1.3) * 14)
                        Breathing(period: 7 + Double(i) * 1.7) {
                            Circle()
                                .fill(orb.kind.halo.opacity(0.85))
                                .frame(width: size, height: size)
                                .blur(radius: 22)
                        }
                        // Fade with volume, so arriving and leaving sounds melt in and out.
                        .opacity(min(1, orb.volume * 3))
                        .blendMode(.screen)
                        .position(x: center.x + cos(angle) * distance + wander.x + drift.x,
                                  y: center.y + sin(angle) * distance + wander.y + drift.y)
                    }
                }
                .compositingGroup()
                .overlay {
                    // A lightning strike lights the halo for a moment.
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.55 * flash), .clear],
                                             center: .center, startRadius: 0, endRadius: proxy.size.width * 0.55))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
                .onChange(of: timeline.date) { _, _ in
                    let strikes = LightningFlash.strikes.pointee
                    if strikes != seenStrikes {
                        seenStrikes = strikes
                        if hasLightning { flash = 1 }
                    } else if flash > 0 {
                        flash = max(0, flash - 0.08)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var hasLightning: Bool { orbs.contains { $0.kind == .lightning && $0.volume > 0.05 } }
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
        .sensoryFeedback(.impact(weight: .medium), trigger: mixer.isPlaying)
        .accessibilityLabel(mixer.isPlaying ? "Pause" : "Play")
    }
}

/// A slim, calm wave under the readout. Its height follows how loud the mix is (smoothed over
/// about half a second) and it drifts slowly sideways, so it feels alive without twitching.
private struct Waveform: View {
    @Environment(Mixer.self) private var mixer
    @State private var level: Double = 0

    var body: some View {
        // Keep animating after pause until the wave has settled flat.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !mixer.isPlaying && level < 0.001)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
            Canvas { ctx, size in
                let mid = size.height / 2
                let amplitude = mid * 0.45 * min(1, level * 4)
                var path = Path()
                let samples = 90
                for i in 0...samples {
                    let x = Double(i) / Double(samples)
                    let edge = sin(x * .pi)   // taper into the edges
                    // Two slow waves at different speeds give a soft, organic shape.
                    let y = 0.65 * sin(x * 2 * .pi * 2.2 - t * 1.8) + 0.35 * sin(x * 2 * .pi * 3.7 + t * 1.2)
                    let p = CGPoint(x: x * size.width, y: mid - y * amplitude * edge)
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                let colors = mixer.byVolume.prefix(3).map(\.kind.orb)
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: colors.isEmpty ? [Theme.mono] : colors + [colors[0]]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                ctx.opacity = mixer.isPlaying ? 0.85 : 0.25
                ctx.drawLayer { glow in
                    glow.addFilter(.blur(radius: 5))
                    glow.stroke(path, with: shading, lineWidth: 3)
                }
                ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
            .onChange(of: timeline.date) { _, _ in
                let peaks = mixer.isPlaying ? mixer.scope.snapshot() : []
                let rms = peaks.isEmpty ? 0 : sqrt(peaks.map { Double($0 * $0) }.reduce(0, +) / Double(peaks.count))
                level += (rms - level) * 0.03   // slow, so loudness changes never jolt the height
            }
        }
        .accessibilityHidden(true)
    }
}
