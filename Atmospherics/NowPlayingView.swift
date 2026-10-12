import SwiftUI

#if os(iOS)
/// Home screen: a breathing halo of the current sounds, the mix name, and the main controls.
/// (The Mac's window, `MacListen`, is built from the same parts below.)
struct NowPlayingView: View {
    @Environment(Mixer.self) private var mixer
    @State private var showLibrary = false
    @State private var showGlobe = false
    @State private var dragX: CGFloat = 0
    @State private var showMixer = false
    @State private var saving = false
    @State private var hint: String?
    /// How many of the one-time hints have been shown.
    @AppStorage("hintStep") private var hintStep = 0
    @AppStorage("tempUnit") private var tempUnit = "auto"
    private var tempUnitLabel: String { tempUnit == "f" ? "°F" : tempUnit == "c" ? "°C" : "Auto" }

    private static let hints = [
        "Swipe left or right to travel",
        "Tap the light to see its layers",
        "Swipe up for your library",
        "Swipe down to change the weather",
        "Hold play for a sleep timer",
    ]

    @State private var weatherToastTask: Task<Void, Never>?

    private func showWeatherToast() {
        weatherToastTask?.cancel()
        let label = mixer.skyOverride == .live ? "Live weather" : mixer.skyOverride.rawValue
        withAnimation(.smooth(duration: 0.25)) { hint = label }
        weatherToastTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.4)) { hint = nil }
        }
    }

    /// Shows each hint once, a few seconds apart, the first times you open the app.
    private func runHints() async {
        while hintStep < Self.hints.count {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.5)) { hint = Self.hints[hintStep] }
            hintStep += 1
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.smooth(duration: 0.5)) { hint = nil }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Menu {
                    if mixer.activePreset != nil {
                        Button("Back to \(mixer.presetReturnName)", systemImage: "arrow.uturn.backward") {
                            withAnimation(.smooth(duration: 0.35)) { mixer.leavePreset() }
                        }
                    } else if mixer.mode == .escape {
                        Button("Home · \(mixer.homeName)", systemImage: "house") {
                            withAnimation(.smooth(duration: 0.35)) { mixer.goHome() }
                        }
                    } else if mixer.following[.match] != true {
                        Button("Follow the weather", systemImage: "arrow.clockwise") { mixer.followWeatherAgain() }
                    }
                    if mixer.isImagining {
                        Button("Back to live weather", systemImage: "arrow.uturn.backward") {
                            withAnimation(.smooth) { mixer.clearOverrides() }
                        }
                        Divider()
                    }
                    Button("Layers", systemImage: "square.3.layers.3d") { showMixer = true }
                    Button("Library", systemImage: "books.vertical") { showLibrary = true }
                    Button("World", systemImage: "globe") { showGlobe = true }
                    Menu("Sleep timer · \(mixer.timer == .off ? "off" : mixer.timer.label)", systemImage: "moon") {
                        ForEach(Mixer.Timer.allCases, id: \.self) { t in
                            Button(t == .off ? "No timer" : "Stop after \(t.label)") { mixer.setTimer(t) }
                        }
                    }
                    Menu("Weather · \(mixer.skyOverride.rawValue)", systemImage: "cloud.sun") {
                        Picker("Weather", selection: Binding(get: { mixer.skyOverride }, set: { mixer.setSky($0) })) {
                            ForEach(Mixer.SkyOverride.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    }
                    Menu("Time of day · \(mixer.timeOverride.rawValue)", systemImage: "sun.and.horizon") {
                        Picker("Time of day", selection: Binding(get: { mixer.timeOverride }, set: { mixer.setTime($0) })) {
                            ForEach(Mixer.TimeOverride.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    }
                    Menu("Temperature · \(tempUnitLabel)", systemImage: "thermometer.medium") {
                        Picker("Temperature", selection: $tempUnit) {
                            Text("Auto").tag("auto")
                            Text("°F").tag("f")
                            Text("°C").tag("c")
                        }
                    }
                    Button("Save this mix", systemImage: "bookmark") { saving = true }
                    if mixer.currentPlaceIsTweaked {
                        Button("Reset \(mixer.currentPlaceName) to default", systemImage: "arrow.counterclockwise") {
                            withAnimation(.smooth) { mixer.resetCurrentPlace() }
                        }
                    }
                    Divider()
                    Button("Show gesture hints again", systemImage: "hand.tap") {
                        hintStep = 0
                        Task { await runHints() }
                    }
                } label: {
                    HStack(spacing: 10) {
                        // A quiet vertical ⋮ so it reads as a menu.
                        // Amber while a weather or time override is on.
                        VStack(spacing: 2.5) {
                            ForEach(0..<3, id: \.self) { _ in Circle().frame(width: 2.5, height: 2.5) }
                        }
                        .foregroundStyle(mixer.isImagining ? Color.oklch(0.8, 0.13, 70) : Theme.mono)
                        .shadow(color: mixer.isImagining ? Color.oklch(0.8, 0.13, 70).opacity(0.6) : .clear, radius: 3)
                        .animation(.smooth, value: mixer.isImagining)
                        Text("ATMOSPHERICS")
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(mixer.isImagining ? "Menu. Weather override on." : "Menu")
                .buttonStyle(.plain)
                Spacer()
                Button { showGlobe = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                        Text(mixer.headerPlace)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("World. \(mixer.headerPlace)")
            }
            .font(Theme.mono(11, .medium))
            .tracking(1.3)
            .foregroundStyle(Theme.mono)

            Carousel(showLibrary: $showLibrary, dragX: $dragX, openMixer: { showMixer = true })
                .frame(minHeight: 420, maxHeight: .infinity)

            .sensoryFeedback(.selection, trigger: mixer.mode)

            Waveform()
                .frame(height: 40)
                .padding(.top, 6)

            // What's playing, and the control for it, side by side along the bottom.
            HStack(spacing: 14) {
                LayerStrip(orbs: mixer.byVolume)
                if mixer.timer != .off {
                    Text(mixer.timer.label)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.mono)
                        .transition(.opacity)
                }
                PlayButton()
            }
            .padding(.top, 14)
            .animation(.smooth, value: mixer.timer)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background { SceneWash(orbs: mixer.byVolume) }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { g in
                let up = -g.translation.height
                guard abs(up) > 80, abs(up) > abs(g.translation.width) * 1.5 else { return }
                if up > 0 {
                    showLibrary = true
                } else {
                    // Swipe down: change the weather.
                    withAnimation(.smooth) { mixer.cycleSky() }
                    showWeatherToast()
                }
            }
        )
        .accessibilityAction(named: "Library") { showLibrary = true }
        .accessibilityAction(named: "Change the weather") { mixer.cycleSky() }
        .accessibilityAction(named: "Layers") { showMixer = true }
        .navigationDestination(isPresented: $showMixer) { MixerView() }
        .overlay(alignment: .bottom) {
            if let hint {
                Text(hint)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.text)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    .padding(.bottom, 130)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    .allowsHitTesting(false)
            }
        }
        .saveMixPrompt(isPresented: $saving)
        .task { await runHints() }
        .sheet(isPresented: $showLibrary) {
            LibraryView(current: mixer.activePreset)
        }
        .fullScreenCover(isPresented: $showGlobe) {
            GlobeView()
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: mixer.shuffleCount)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: mixer.skyOverride)
    }

}

enum Route: Hashable { case mixer }
#endif

/// The halo, title, weather and layers as a page, with the previous and next places beside it.
/// Drag follows the finger 1:1; let go past a quarter of the width (or flick) to land on the neighbour.
/// On a Mac, two fingers on the trackpad do the same, and the keyboard and menus slide it too.
struct Carousel: View {
    @Environment(Mixer.self) private var mixer
    @Binding var showLibrary: Bool
    @Binding var dragX: CGFloat
    let openMixer: () -> Void
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
            #if os(macOS)
            .background(TrackpadSwipe(changed: { follow($0, width: w) },
                                      ended: { release(projected: $0, width: w, step: step) }))
            #endif
            .onChange(of: mixer.travelRequest) { _, request in
                guard let request, !settling else { return }
                land(forward: request.forward, step: step, duration: 0.55)
            }
        }
        .onAppear { mixer.carouselShowing = true }
        .onDisappear { mixer.carouselShowing = false }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: pastThreshold) { _, now in now }
        .accessibilityAction(named: "Travel somewhere new") { mixer.travel(forward: true) }
        .accessibilityAction(named: "Go back") { mixer.travel(forward: false) }
    }

    /// The live page: the real mix, with the title opening the Library.
    private var currentPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Halo(orbs: mixer.byVolume)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { openMixer() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Open layers")
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
            PageLines(line: mixer.weather.line)
        }
    }

    private func drag(width: CGFloat, step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { g in
                guard abs(g.translation.width) > abs(g.translation.height) else { return }
                follow(g.translation.width, width: width)
            }
            .onEnded { g in release(projected: g.predictedEndTranslation.width, width: width, step: step) }
    }

    /// The pages follow the finger.
    private func follow(_ translation: CGFloat, width: CGFloat) {
        guard !settling else { return }
        var x = translation
        // Resist past an edge with nothing beyond it.
        if (x < 0 && mixer.next == nil) || (x > 0 && mixer.previous == nil) { x = 40 * tanh(x / 120) }
        dragX = x
        pastThreshold = abs(x) > width * 0.25
    }

    /// Let go: `projected` is where a flick would carry the pages.
    private func release(projected: CGFloat, width: CGFloat, step: CGFloat) {
        guard !settling else { return }
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
        land(forward: forward, step: step)
    }

    /// Slides the rest of the way to the neighbour, switching the sound as it goes.
    private func land(forward: Bool, step: CGFloat, duration: Double = 0.3) {
        settling = true
        // Snapshot both pages, then switch the sound right away.
        let outgoing = Mixer.Page(title: mixer.title, line: mixer.weather.line, orbs: mixer.byVolume)
        if let dest = forward ? mixer.next : mixer.previous {
            frozen = (outgoing, mixer.page(for: dest), forward)
        }
        mixer.travel(forward: forward)
        withAnimation(.spring(duration: duration, bounce: 0)) {
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
            PageLines(line: page.line)
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
    var body: some View {
        Text(line)
            .font(Theme.body(15))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 10)
    }
}

/// The sounds playing, loudest first, each with a dot in its light's color. Always one line:
/// as many as fit, then "+2" for the rest, so it never wraps.
struct LayerStrip: View {
    let orbs: [Orb]
    var color: Color = Theme.mono

    private var kinds: [SoundKind] {
        var seen = Set<SoundKind>()
        return orbs.sorted { $0.volume > $1.volume }
            .filter { $0.volume >= 0.05 && seen.insert($0.kind).inserted }
            .map(\.kind)
    }

    var body: some View {
        let kinds = kinds
        ViewThatFits(in: .horizontal) {
            ForEach(Array((1...max(1, kinds.count)).reversed()), id: \.self) { n in
                row(Array(kinds.prefix(n)), more: kinds.count - n)
            }
        }
        .font(Theme.mono(11))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kinds.map(\.name).joined(separator: ", "))
    }

    private func row(_ shown: [SoundKind], more: Int) -> some View {
        HStack(spacing: 14) {
            ForEach(shown, id: \.self) { kind in
                HStack(spacing: 6) {
                    Circle().fill(kind.orb).frame(width: 5, height: 5)
                    Text(kind.short)
                }
            }
            if more > 0 { Text("+\(more)") }
        }
        .fixedSize()
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
    @State private var choosingTimer = false
    @State private var held = 0

    var body: some View {
        // A quiet ring rather than a big disc, so the scene stays the focus.
        ZStack {
            Circle().strokeBorder(Theme.text.opacity(0.8), lineWidth: 1.5)
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
        .contentShape(Circle())
        // Tap to play or pause; hold for a sleep timer.
        .onTapGesture { mixer.togglePlayback() }
        .onLongPressGesture(minimumDuration: 0.45) {
            held += 1
            choosingTimer = true
        }
        .confirmationDialog("Sleep timer", isPresented: $choosingTimer, titleVisibility: .visible) {
            ForEach(Mixer.Timer.allCases, id: \.self) { t in
                Button(t == .off ? "No timer" : "Stop after \(t.label)" + (t == mixer.timer ? "  ✓" : "")) {
                    mixer.setTimer(t)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: mixer.isPlaying)
        .sensoryFeedback(.impact(weight: .heavy), trigger: held)
        .sensoryFeedback(.selection, trigger: mixer.timer)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(mixer.isPlaying ? "Pause" : "Play")
        .accessibilityHint("Hold for a sleep timer")
        .accessibilityAction { mixer.togglePlayback() }
        .accessibilityAction(named: "Sleep timer") { choosingTimer = true }
    }
}

/// A slim, calm wave under the readout. Its height follows how loud the mix is (smoothed over
/// about half a second) and it drifts slowly sideways, so it feels alive without twitching.
struct Waveform: View {
    @Environment(Mixer.self) private var mixer
    @State private var level: Double = 0

    var body: some View {
        // Keep animating after pause until the wave has settled flat.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !mixer.isPlaying && level < 0.001)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
            Canvas { ctx, size in
                let mid = size.height / 2
                let amplitude = mid * 0.45 * min(1, level * 7)
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
