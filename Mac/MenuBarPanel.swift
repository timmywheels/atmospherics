import SwiftUI

/// The menu bar control, in the colors of what's playing: what it is, play and travel, the volume,
/// and one quiet line for the sleep timer, Search, the window and Quit.
struct MenuBarPanel: View {
    @Environment(Mixer.self) private var mixer
    @Environment(MacNavigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    @AppStorage("tempUnit") private var tempUnit = "auto"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nowPlaying
                .padding(.horizontal, 18)
                .padding(.top, 18)

            transport
                .padding(.top, 14)
                .padding(.horizontal, 18)

            VolumeLine()
                .frame(height: 32)
                .padding(.top, 10)
                .padding(.horizontal, 18)

            Rectangle().fill(Theme.hairline).frame(height: 1)
                .padding(.top, 12)

            footer
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(width: 300)
        .foregroundStyle(Theme.text)
        .background { SceneWash(orbs: mixer.byVolume) }
        .preferredColorScheme(.dark)
        .haptic(.thud, trigger: mixer.isPlaying)
        .haptic(.thud, trigger: mixer.shuffleCount)
    }

    // MARK: What's playing

    private var nowPlaying: some View {
        HStack(spacing: 14) {
            HaloArt(lights: mixer.byVolume.prefix(4).map {
                .init(hue: $0.kind.hue, chroma: $0.kind == .grey ? 0.1 : 1, volume: $0.volume)
            })
            .frame(width: 52, height: 52)
            .background(Circle().fill(.black.opacity(0.25)))
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(mixer.title)
                    .font(Theme.display(26))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(Theme.label(10.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// "Fog in Newport · 14°", or the place for a Library mix.
    private var subtitle: String {
        let line = mixer.weather.line
        let temp = mixer.weather.temp
        return temp.isEmpty ? line : "\(line) · \(temp)"
    }

    private var transport: some View {
        HStack {
            roundButton("chevron.left", size: 14, label: "Go back") { mixer.requestTravel(forward: false) }
                .disabled(mixer.previous == nil)
            Spacer()
            Button { mixer.togglePlayback() } label: {
                ZStack {
                    Circle().strokeBorder(Theme.text.opacity(0.85), lineWidth: 1.5)
                    Image(systemName: mixer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17))
                        .offset(x: mixer.isPlaying ? 0 : 1.5)
                }
                .frame(width: 50, height: 50)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mixer.isPlaying ? "Pause" : "Play")
            Spacer()
            roundButton("chevron.right", size: 14, label: "Travel somewhere new") { mixer.requestTravel(forward: true) }
        }
        .padding(.horizontal, 30)
    }

    private func roundButton(_ symbol: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: Footer

    /// The sleep timer, then Search, the window and Quit.
    private var footer: some View {
        HStack(spacing: 0) {
            TimerMenu()
            Spacer()
            footerButton(help: "Search the Library  ⌘K") {
                navigation.search()
                open(.library)
            } label: { Text("Search…") }
            footerButton(help: "Open the Atmospherics window") { open(navigation.tab) } label: { Text("Open") }
            footerButton(help: "Quit Atmospherics  ⌘Q") { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 11, weight: .medium))
            }
            .keyboardShortcut("q")
            .accessibilityLabel("Quit")
        }
    }

    private func footerButton(help: String, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .font(Theme.label(12))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle(corner: 6))
        .help(help)
    }

    private func open(_ tab: MacNavigation.Tab) {
        navigation.tab = tab
        openWindow(id: MacNavigation.mainWindow)
        NSApp.activate()
    }
}

/// A row that lights up under the pointer, like a menu item.
private struct MenuRowStyle: ButtonStyle {
    var corner: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, corner: corner)
    }

    private struct Row: View {
        let configuration: Configuration
        let corner: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: corner)
                    .fill(.white.opacity(configuration.isPressed ? 0.14 : hovering ? 0.08 : 0)))
                .onHover { hovering = $0 }
        }
    }
}

/// The menu bar icon: the halo as a small soft orb with faded edges, like the app icon. While
/// playing it takes the colors of what's playing and breathes, slowly: a breath every six seconds,
/// its lights swaying a little with it. Paused, it's grey and still. A faint dark disc under it
/// keeps it legible on a light menu bar.
struct MenuBarIcon: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        Group {
            if mixer.isPlaying {
                Image(nsImage: Self.breath(mixer.byVolume)[IconBreath.shared.frame % Self.frames])
            } else {
                Image(nsImage: Self.paused)
            }
        }
        .accessibilityLabel(mixer.isPlaying ? "Atmospherics, playing" : "Atmospherics")
    }

    /// One breath: six seconds at five frames a second (`IconBreath`). Each breath is drawn once and
    /// kept for its colors, so the icon never makes the same picture twice.
    static let frames = 30
    private static var breaths: [[Double]: [NSImage]] = [:]

    /// One breath's frames in the loudest three sounds' colors, a little softened toward grey so
    /// the menu bar stays calm.
    private static func breath(_ orbs: [Orb]) -> [NSImage] {
        let hues = orbs.prefix(3).map(\.kind.hue)
        let key = hues.isEmpty ? [55.0, 235, 330] : (0..<3).map { hues[$0 % hues.count] }
        if let kept = breaths[key] { return kept }
        if breaths.count > 24 { breaths.removeAll() }
        let tints = key.map { NSColor(Color.oklch(0.74, 0.15, $0)).blended(withFraction: 0.2, of: .gray) ?? .gray }
        let made = (0..<frames).map { image(tints: tints, phase: Double($0) / Double(frames)) }
        breaths[key] = made
        return made
    }

    /// The app icon's warm, blue and pink lights, mostly grey and dim.
    private static let paused = image(
        tints: [55.0, 235, 330].map { NSColor(Color.oklch(0.7, 0.16, $0)).blended(withFraction: 0.7, of: .gray) ?? .gray },
        phase: nil)

    /// Still and dim with no `phase` (paused); otherwise that moment of a breath, from 0 to 1.
    private static func image(tints: [NSColor], phase: Double?) -> NSImage {
        let breath = CGFloat(phase.map { 0.5 - 0.5 * cos($0 * 2 * .pi) } ?? 0)
        let sway = CGFloat(phase.map { 0.35 * sin($0 * 2 * .pi) } ?? 0)
        let alpha: CGFloat = phase == nil ? 0.5 : 0.82 + 0.18 * breath
        let swell: CGFloat = phase == nil ? 1 : 0.95 + 0.05 * breath
        let middle: CGFloat = phase == nil ? 0.6 : 0.42
        return NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: 9, y: 9)
            disc(ctx, center, 8.8, NSColor(srgbRed: 0.05, green: 0.055, blue: 0.075, alpha: 0.7 * alpha), hold: 0.55)
            // Three lights, each a little off center, swaying around the middle as it breathes.
            let offsets = [CGPoint(x: 1.5, y: 1.3), CGPoint(x: -1.7, y: 0.4), CGPoint(x: 0.5, y: -1.7)]
            ctx.setBlendMode(.screen)
            for (tint, o) in zip(tints, offsets) {
                let at = CGPoint(x: center.x + o.x * cos(sway) - o.y * sin(sway), y: center.y + o.x * sin(sway) + o.y * cos(sway))
                disc(ctx, at, 7.6 * swell, tint.withAlphaComponent(0.9 * alpha), hold: 0.15)
            }
            // The bright middle where they meet.
            disc(ctx, center, 5.2 * swell, NSColor(white: 1, alpha: middle * alpha), hold: 0.05)
            ctx.setBlendMode(.normal)
            return true
        }
    }

    /// A soft disc: solid out to `hold` of its radius, then fading smoothly to nothing at the edge.
    private static func disc(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ color: NSColor, hold: CGFloat) {
        let stops = (0...10).map { CGFloat($0) / 10 }
        let colors = stops.map { t -> CGColor in
            let u = max(0, (t - hold) / (1 - hold))
            return color.withAlphaComponent(color.alphaComponent * (1 - u * u * (3 - 2 * u))).cgColor
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors as CFArray, locations: stops) else { return }
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }
}

/// The menu bar icon's breath: a frame that steps five times a second while something plays, the
/// displays are awake and motion isn't reduced. Each step is a plain change that redraws the icon
/// once. (A TimelineView in a menu bar icon makes SwiftUI redraw it nonstop and holds up the app.)
@MainActor
@Observable
final class IconBreath {
    static let shared = IconBreath()
    private(set) var frame = 0
    @ObservationIgnored private var timer: Timer?

    /// Breathes while the mixer plays, from now on.
    func follow(_ mixer: Mixer) {
        withObservationTracking {
            run(mixer.isPlaying && !Displays.shared.asleep && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        } onChange: {
            Task { @MainActor in self.follow(mixer) }
        }
    }

    private func run(_ on: Bool) {
        guard on != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        guard on else { return }
        let step = Timer(timeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated { IconBreath.shared.frame &+= 1 }
        }
        step.tolerance = 0.05
        RunLoop.main.add(step, forMode: .common)
        timer = step
    }
}

/// Whether the displays are asleep, so the menu bar icon can rest through a night of sleep sounds
/// instead of redrawing for no one.
@MainActor
@Observable
final class Displays {
    static let shared = Displays()
    private(set) var asleep = false

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = true }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = false }
        }
    }
}
