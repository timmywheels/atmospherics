import SwiftUI

/// The menu bar control, in the colors of what's playing: play, travel, a sleep timer, and every
/// atmosphere a click away, without opening the window.
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

            timer
                .padding(.top, 16)
                .padding(.horizontal, 18)

            Rectangle().fill(Theme.hairline).frame(height: 1)
                .padding(.top, 16)

            destinations
                .frame(height: 248)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 300)
        .foregroundStyle(Theme.text)
        .background { SceneWash(orbs: mixer.byVolume) }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium), trigger: mixer.isPlaying)
        .sensoryFeedback(.impact(weight: .medium), trigger: mixer.shuffleCount)
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
                    .font(Theme.display(22))
                    .tracking(-0.4)
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

    private var timer: some View {
        HStack(spacing: 6) {
            Text("SLEEP")
                .font(Theme.caps(10))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            Spacer()
            ForEach(Mixer.Timer.allCases, id: \.self) { t in
                let selected = mixer.timer == t
                Button { mixer.setTimer(t) } label: {
                    Text(t.label)
                        .font(Theme.label(11, .medium))
                        .foregroundStyle(selected ? Theme.background : Theme.text)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(selected ? Theme.text : .clear))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t == .off ? "No sleep timer" : "Stop after \(t.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: mixer.timer)
    }

    // MARK: Where to go

    private var destinations: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    placeRow(id: "home", name: "Home" + (mixer.home.map { " · \($0.place)" } ?? ""),
                             temperature: mixer.home?.temperature, color: Theme.text,
                             current: mixer.activePreset == nil && mixer.mode == .match) {
                        mixer.goHome()
                        if !mixer.isPlaying { mixer.play() }
                    }
                    .padding(.top, 6)
                    header("Atmospheres")
                    ForEach(Atmosphere.curated) { a in
                        let page = mixer.page(for: .atmosphere(a))
                        let top = page.orbs.max { $0.volume < $1.volume }?.kind
                        placeRow(id: a.id, name: page.title, temperature: mixer.liveSource(for: a)?.conditions.temperature,
                                 color: top?.orb ?? Theme.text, current: isCurrent(a)) {
                            mixer.go(to: a)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .onAppear {
                if let a = mixer.atmosphere, mixer.mode == .atmosphere { proxy.scrollTo(a.id, anchor: .center) }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.caps(10))
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func isCurrent(_ atmosphere: Atmosphere) -> Bool {
        mixer.activePreset == nil && mixer.mode == .atmosphere && mixer.atmosphere == atmosphere
    }

    private func placeRow(id: String, name: String, temperature: String?, color: Color, current: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.8), radius: current ? 4 : 0)
                Text(name)
                    .font(Theme.body(13, current ? .medium : .regular))
                    .lineLimit(1)
                Spacer()
                if current {
                    Text(mixer.isPlaying ? "Playing" : "Here")
                        .font(Theme.label(10, .medium))
                        .foregroundStyle(Theme.secondary)
                }
                if let temperature {
                    Text(temperature)
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(current ? Color.white.opacity(0.07) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
        .id(id)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                open(navigation.tab)
            } label: {
                footerRow("Open Atmospherics", shortcut: nil)
            }
            .buttonStyle(MenuRowStyle(corner: 6))
            Button {
                open(.teleport)
            } label: {
                footerRow("Teleport…", shortcut: "⌘K")
            }
            .buttonStyle(MenuRowStyle(corner: 6))
            Button {
                NSApp.terminate(nil)
            } label: {
                footerRow("Quit", shortcut: "⌘Q")
            }
            .buttonStyle(MenuRowStyle(corner: 6))
            .keyboardShortcut("q")
        }
    }

    private func footerRow(_ title: String, shortcut: String?) -> some View {
        HStack {
            Text(title).font(Theme.body(13))
            Spacer()
            if let shortcut { Text(shortcut).font(Theme.label(11)).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
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

/// The menu bar icon: the halo as a small soft orb with faded edges, like the app icon, kept
/// neutral (the halo's colors only as a faint tint). A little brighter while playing. A faint dark
/// disc under it keeps it legible on a light menu bar.
struct MenuBarIcon: View {
    @Environment(Mixer.self) private var mixer

    var body: some View {
        Image(nsImage: mixer.isPlaying ? Self.playing : Self.paused)
            .accessibilityLabel(mixer.isPlaying ? "Atmospherics, playing" : "Atmospherics")
    }

    private static let playing = image(brightness: 0.75)
    private static let paused = image(brightness: 0.5)

    private static func image(brightness: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx, alpha: brightness)
            return true
        }
    }

    private static func draw(in ctx: CGContext, alpha: CGFloat) {
        let center = CGPoint(x: 9, y: 9)
        disc(ctx, center, 8.8, NSColor(srgbRed: 0.05, green: 0.055, blue: 0.075, alpha: 0.7 * alpha), hold: 0.55)
        // The app icon's warm, blue and pink lights, mostly grey, each a little off center.
        let tints = [55.0, 235, 330].map { NSColor(Color.oklch(0.7, 0.16, $0)).blended(withFraction: 0.7, of: .gray) ?? .gray }
        let offsets = [CGPoint(x: 1.5, y: 1.3), CGPoint(x: -1.7, y: 0.4), CGPoint(x: 0.5, y: -1.7)]
        ctx.setBlendMode(.screen)
        for (tint, offset) in zip(tints, offsets) {
            disc(ctx, CGPoint(x: center.x + offset.x, y: center.y + offset.y), 7.6, tint.withAlphaComponent(0.9 * alpha), hold: 0.15)
        }
        // The bright middle where they meet.
        disc(ctx, center, 5.2, NSColor(white: 1, alpha: 0.6 * alpha), hold: 0.05)
        ctx.setBlendMode(.normal)
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
