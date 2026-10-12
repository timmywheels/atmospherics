import SwiftUI

/// Home screen: a breathing halo of the current sounds, the mix name, and the main controls.
struct NowPlayingView: View {
    @Environment(Mixer.self) private var mixer
    @State private var showLibrary = false
    @State private var showGlobe = false
    @State private var dragX: CGFloat = 0
    @AppStorage("hasSwiped") private var hasSwiped = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ATMOSPHERICS")
                Spacer()
                Button { showGlobe = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mixer.activePreset == nil ? "globe" : "books.vertical")
                        Text(mixer.weather.temp.isEmpty ? mixer.weather.place : "\(mixer.weather.place) \(mixer.weather.temp)")
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

            Carousel(showLibrary: $showLibrary, dragX: $dragX, hasSwiped: $hasSwiped)
                .frame(minHeight: 420, maxHeight: .infinity)

            // Away: a quiet way home. At home but edited: a way back to following the weather.
            // A fixed-height slot: the line fades in and out without moving anything.
            ZStack(alignment: .leading) {
                Text(" ").hidden()
                if mixer.activePreset != nil {
                    Button { withAnimation(.smooth(duration: 0.35)) { mixer.leavePreset() } } label: {
                        Text("← Back to \(mixer.presetReturnName)")
                    }
                } else if mixer.mode == .escape {
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

            VStack(spacing: 18) {
                PlayButton()

                // Three evenly spaced tools under the play button.
                HStack(spacing: 0) {
                    Button { showLibrary = true } label: {
                        ToolIcon(glyph: .library)
                    }
                    .accessibilityLabel("Library")

                    Button { mixer.cycleTimer() } label: {
                        ToolIcon(glyph: .timer, badge: mixer.timer == .off ? nil : mixer.timer.label)
                    }
                    .accessibilityLabel("Sleep timer, \(mixer.timer.label). Tap to change.")
                    .sensoryFeedback(.selection, trigger: mixer.timer)

                    NavigationLink(value: Route.mixer) {
                        ToolIcon(glyph: .mixer)
                    }
                    .accessibilityLabel("Mixer")
                }
            }
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
        .sensoryFeedback(.impact(weight: .medium), trigger: mixer.shuffleCount)
    }

}

enum Route: Hashable { case mixer }

/// Hairline glyphs drawn to match the app's thin type, instead of stock symbols.
enum Glyph { case library, timer, mixer }

private struct ToolIcon: View {
    let glyph: Glyph
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Canvas { ctx, size in
                let s = min(size.width, size.height)
                let o = CGPoint(x: (size.width - s) / 2, y: (size.height - s) / 2)
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
                let line = StrokeStyle(lineWidth: 1.2, lineCap: .round)
                var path = Path()
                switch glyph {
                case .library:
                    // Book spines on a shelf: three upright, one leaning.
                    for x in [0.26, 0.4, 0.54] {
                        path.move(to: p(x, 0.24))
                        path.addLine(to: p(x, 0.8))
                    }
                    path.move(to: p(0.66, 0.8))
                    path.addLine(to: p(0.82, 0.28))
                    ctx.stroke(path, with: .foreground, style: line)
                case .timer:
                    // A thin crescent: a disc with an offset disc cut out of it.
                    ctx.drawLayer { layer in
                        layer.fill(Path(ellipseIn: CGRect(origin: p(0.16, 0.16), size: CGSize(width: s * 0.68, height: s * 0.68))),
                                   with: .foreground)
                        layer.blendMode = .destinationOut
                        layer.fill(Path(ellipseIn: CGRect(origin: p(0.3, 0.06), size: CGSize(width: s * 0.64, height: s * 0.64))),
                                   with: .color(.black))
                    }
                case .mixer:
                    // The field in miniature: the ring, its centre point, and one light drifting in it.
                    path.addEllipse(in: CGRect(origin: p(0.14, 0.14), size: CGSize(width: s * 0.72, height: s * 0.72)))
                    ctx.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    for (x, y, r) in [(0.5, 0.5, 0.035), (0.36, 0.62, 0.085)] {
                        ctx.fill(Path(ellipseIn: CGRect(x: o.x + (x - r) * s, y: o.y + (y - r) * s, width: 2 * r * s, height: 2 * r * s)),
                                 with: .foreground)
                    }
                }
            }
            .frame(width: 22, height: 22)
            if let badge {
                Text(badge).font(Theme.mono(10))
            }
        }
        .opacity(0.7)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The halo, title, weather and layers as a page, with the previous and next places beside it.
/// Drag follows the finger 1:1; let go past a quarter of the width (or flick) to land on the neighbour.
private struct Carousel: View {
    @Environment(Mixer.self) private var mixer
    @Binding var showLibrary: Bool
    @Binding var dragX: CGFloat
    @Binding var hasSwiped: Bool
    @State private var pastThreshold = false
    @State private var settling = false
    @State private var saving = false
    /// While a swipe lands, the two pages are drawn from a snapshot so the sound can switch at
    /// release without the sliding pages changing under the finger.
    @State private var frozen: (outgoing: Mixer.Page, incoming: Mixer.Page, forward: Bool)?

    private let gap: CGFloat = 56

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let step = w + gap
            ZStack(alignment: .topLeading) {
                if let f = frozen {
                    PageView(page: f.outgoing).frame(width: w).offset(x: dragX)
                    PageView(page: f.incoming).frame(width: w).offset(x: (f.forward ? step : -step) + dragX)
                } else {
                    if let prev = mixer.previous {
                        PageView(page: mixer.page(for: prev)).frame(width: w).offset(x: -step + dragX)
                    }
                    currentPage.frame(width: w).offset(x: dragX)
                    if let next = mixer.next {
                        PageView(page: mixer.page(for: next)).frame(width: w).offset(x: step + dragX)
                    }
                }
            }
            .frame(width: w, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(drag(width: w, step: step))
            .overlay(alignment: .center) {
                if !hasSwiped {
                    Text("← swipe to travel →")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.mono.opacity(0.7))
                        .offset(y: proxy.size.height * 0.18)
                        .allowsHitTesting(false)
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: pastThreshold) { _, now in now }
        .accessibilityAction(named: "Travel somewhere new") { mixer.travel(forward: true) }
        .accessibilityAction(named: "Go back") { mixer.travel(forward: false) }
    }

    /// The live page: the real mix, with the title opening the Library.
    private var currentPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Halo(orbs: mixer.byVolume)
                .frame(maxHeight: .infinity)
            Button { showLibrary = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    PageTitle(text: mixer.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.mono)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the library")
            .contextMenu {
                Button("Save this mix", systemImage: "bookmark") { saving = true }
                Button("Library", systemImage: "books.vertical") { showLibrary = true }
            }
            .saveMixPrompt(isPresented: $saving)
            PageLines(line: mixer.weather.line, layers: mixer.layersLine)
        }
    }

    private func drag(width: CGFloat, step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { g in
                guard !settling, abs(g.translation.width) > abs(g.translation.height) else { return }
                var x = g.translation.width
                // Resist past an edge with nothing beyond it.
                if (x < 0 && mixer.next == nil) || (x > 0 && mixer.previous == nil) { x = 40 * tanh(x / 120) }
                dragX = x
                pastThreshold = abs(x) > width * 0.25
            }
            .onEnded { g in
                guard !settling else { return }
                let projected = g.predictedEndTranslation.width
                let forward = dragX < 0
                // Travel only if the finger ends up past a quarter of the way, or flicks onward;
                // pulling back toward the start cancels, it never sends you the other way.
                let sameWay = dragX != 0 && (projected < 0) == forward
                let commit = sameWay && (abs(dragX) > width * 0.25 || abs(projected) > width * 0.6)
                    && (forward ? mixer.next != nil : mixer.previous != nil)
                pastThreshold = false
                guard commit else {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) { dragX = 0 }
                    return
                }
                settling = true
                // Snapshot both pages, then switch the sound right away.
                let outgoing = Mixer.Page(title: mixer.title, line: mixer.weather.line,
                                          layers: mixer.layersLine, orbs: mixer.byVolume)
                if let dest = forward ? mixer.next : mixer.previous {
                    frozen = (outgoing, mixer.page(for: dest), forward)
                }
                mixer.travel(forward: forward)
                withAnimation(.spring(duration: 0.3, bounce: 0)) {
                    dragX = forward ? -step : step
                } completion: {
                    // The destination is centred and is already the live page: swap without a jump.
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        frozen = nil
                        dragX = 0
                    }
                    settling = false
                    withAnimation { hasSwiped = true }
                }
            }
    }
}

/// A neighbouring place, previewed with its live weather and sounds.
private struct PageView: View {
    let page: Mixer.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Halo(orbs: page.orbs.sorted { $0.volume > $1.volume })
                .frame(maxHeight: .infinity)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                PageTitle(text: page.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.mono)
                    .hidden()
            }
            PageLines(line: page.line, layers: page.layers)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PageTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.display(44))
            .tracking(-1.3)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

private struct PageLines: View {
    let line: String
    let layers: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(line)
                .font(Theme.body(15))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 10)
            // Always two lines tall, so pages line up whatever their sounds.
            Text(layers)
                .font(Theme.mono(11))
                .lineSpacing(4)
                .foregroundStyle(Theme.mono)
                .lineLimit(2, reservesSpace: true)
                .padding(.top, 14)
        }
    }
}

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
