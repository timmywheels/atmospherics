import CoreLocation
#if os(iOS)
import ActivityKit
import WidgetKit
#endif
import AVFoundation
import MediaPlayer
import SwiftUI
import Observation

/// Which field is playing, each kept apart so going from one to another and back finds it as it
/// was: `match` your own weather, `escape` a real place's, `atmosphere` a scene by name ("a log
/// cabin in a snowstorm"), and `mix` a Library mix or one of yours, apart from any place.
enum Mode: String, Codable, CaseIterable {
    case match, escape, atmosphere, mix
}

/// A sound placed on the field. Position is 0…1 in both axes; the center (0.5, 0.5) is full volume
/// and the rim is silent.
struct Orb: Identifiable, Codable, Equatable {
    var id = UUID()
    let kind: SoundKind
    var x: Double
    var y: Double

    var volume: Double { max(0, min(1, 1 - hypot(x - 0.5, y - 0.5) / 0.5)) }
}

/// App state: what's on the field in each mode, playback, and the sleep timer.
@MainActor
@Observable
final class Mixer {
    enum Timer: CaseIterable {
        case off, thirtyMinutes, oneHour, twoHours, eightHours

        var seconds: TimeInterval? {
            switch self {
            case .off: nil
            case .thirtyMinutes: 30 * 60
            case .oneHour: 60 * 60
            case .twoHours: 2 * 60 * 60
            case .eightHours: 8 * 60 * 60
            }
        }

        var label: String {
            switch self {
            case .off: "off"
            case .thirtyMinutes: "30m"
            case .oneHour: "1h"
            case .twoHours: "2h"
            case .eightHours: "8h"
            }
        }
    }

    private(set) var mode: Mode = .match
    private(set) var fields: [Mode: [Orb]]
    private(set) var titles: [Mode: String]
    private(set) var isPlaying = false
    private(set) var timer: Timer = .eightHours
    var errorMessage: String?

    // Weather
    enum WeatherState { case loading, ready, locationOff, failed }
    private(set) var weatherState: WeatherState = .loading
    /// Live weather as fetched. A place is always its real weather now; imagined weather is what
    /// a scene is for.
    private var liveHome: Conditions?
    private var liveEscape: (place: Place, conditions: Conditions)?
    private var livePlaceConditions: [String: Conditions] = [:]

    var home: Conditions? { liveHome }
    var escape: (place: Place, conditions: Conditions)? { liveEscape }
    var placeConditions: [String: Conditions] { livePlaceConditions }
    /// A place the user chose. When nil, Escape picks the place least like home.
    private(set) var pinnedPlace: Place?
    /// Places found through search, newest first.
    private(set) var customPlaces: [Place] = []
    /// Your places first, then the built-in ones (each once: one you've added isn't listed twice).
    var allPlaces: [Place] { customPlaces + Place.all.filter { p in !customPlaces.contains { $0.name == p.name } } }

    /// A built-in place you've added keeps its current sounds, not a copy from the day you added it.
    private static func refreshed(_ place: Place) -> Place {
        let here = CLLocation(latitude: place.latitude, longitude: place.longitude)
        guard let builtIn = Place.all.first(where: {
            $0.name == place.name && here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < 50_000
        }) else { return place }
        return Place(name: builtIn.name, country: builtIn.country, region: .yours, latitude: builtIn.latitude,
                     longitude: builtIn.longitude, signature: builtIn.signature, climate: builtIn.climate,
                     wetMonths: builtIn.wetMonths, seasonal: builtIn.seasonal)
    }

    /// Set while moving between places, for a quicker crossfade than weather drift.
    @ObservationIgnored private var traveling = false
    private(set) var visualTarget: [Orb]?

    /// Bumps on every random jump, so views can animate and play a haptic.
    private(set) var shuffleCount = 0
    /// Whether each mode's field is following the weather, or the user has taken over.
    private(set) var following: [Mode: Bool]

    @ObservationIgnored private let engine = NoiseEngine()
    var scope: Scope { engine.scope }
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var timerWork: DispatchWorkItem?
    @ObservationIgnored private let weatherService = WeatherService()
    @ObservationIgnored private lazy var location = LocationProvider()
    @ObservationIgnored private var lastWeatherFetch: Date?
    @ObservationIgnored private var transition: Task<Void, Never>?

    /// How loud Atmospherics plays, on its own scale apart from the system volume, so a soundscape
    /// can sit low while notifications stay loud. As on the slider, 0…1; the gain is its square,
    /// so even steps sound even.
    var volume: Double = 1 {
        didSet {
            engine.setVolume(Float(volume * volume))
            defaults.set(volume, forKey: "volume")
        }
    }

    init() {
        let savedVolume = defaults.object(forKey: "volume") as? Double ?? 1
        volume = savedVolume
        engine.setVolume(Float(savedVolume * savedVolume))
        if let data = defaults.data(forKey: "fields"),
           let saved = try? JSONDecoder().decode([String: [Orb]].self, from: data) {
            fields = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0, saved[$0.rawValue] ?? []) })
        } else {
            // The design's starting fields.
            fields = [
                .match: [Orb(kind: .brown, x: 0.5, y: 0.36), Orb(kind: .rain, x: 0.68, y: 0.62),
                         Orb(kind: .wind, x: 0.24, y: 0.68), Orb(kind: .thunder, x: 0.84, y: 0.22)],
                .escape: [Orb(kind: .ocean, x: 0.44, y: 0.58), Orb(kind: .fire, x: 0.63, y: 0.38),
                          Orb(kind: .birds, x: 0.2, y: 0.26), Orb(kind: .green, x: 0.74, y: 0.8)],
            ]
        }
        titles = [
            .match: defaults.string(forKey: "title.match") ?? "Attic Rain",
            .escape: defaults.string(forKey: "title.escape") ?? "",
            .atmosphere: defaults.string(forKey: "title.atmosphere") ?? "",
            .mix: defaults.string(forKey: "title.mix") ?? "",
        ]
        following = [
            .match: defaults.object(forKey: "following.match") as? Bool ?? true,
            .escape: defaults.object(forKey: "following.escape") as? Bool ?? true,
            .atmosphere: defaults.object(forKey: "following.atmosphere") as? Bool ?? true,
            .mix: false,
        ]
        atmosphere = defaults.data(forKey: "atmosphere").flatMap { try? JSONDecoder().decode(Atmosphere.self, from: $0) }
        if let raw = defaults.string(forKey: "mode"), let saved = Mode(rawValue: raw) { mode = saved }
        customPlaces = (defaults.array(forKey: "customPlaces") as? [[String: Any]] ?? []).compactMap(Place.init(dictionary:)).map(Self.refreshed)
        pinnedPlace = defaults.string(forKey: "pinnedPlace").flatMap { name in allPlaces.first { $0.name == name } }
        // Places stopped taking an imagined sky or time: once, say so to anyone who'd set one.
        let imagined = ["skyOverride", "timeOverride"].contains { (defaults.string(forKey: $0) ?? "Live") != "Live" }
        ["skyOverride", "timeOverride"].forEach { defaults.removeObject(forKey: $0) }
        tweaks = defaults.dictionary(forKey: "placeTweaks") as? [String: [String: Double]] ?? [:]
        paces = (defaults.dictionary(forKey: "paces") as? [String: String] ?? [:]).reduce(into: [:]) { all, entry in
            if let kind = SoundKind(rawValue: entry.key), let pace = Pace(rawValue: entry.value) { all[kind] = pace }
        }
        for (kind, pace) in paces { engine.setPace(pace.rate, for: kind) }
        if let data = defaults.data(forKey: "savedMixes"), let saved = try? JSONDecoder().decode([SavedMix].self, from: data) {
            // Layers was the mixer once, and Topology for a while.
            savedMixes = saved.map { saved in
                var mix = saved
                for old in ["Made in the mixer", "Made in Topology"] {
                    mix.origin = mix.origin.replacingOccurrences(of: old, with: "Made in Layers")
                }
                return mix
            }
        }
        activePreset = defaults.string(forKey: "activePreset").flatMap { id in
            Preset.all.first { $0.id == id } ?? savedMixes.first { $0.id.uuidString == id }?.preset
        }
        if mode == .atmosphere && atmosphere == nil { mode = .match }
        migrateToOwnSlots()
        if mode == .mix && activePreset == nil { mode = .match }
        lens = activePreset.map { $0.tag.map(Lens.init) } ?? (mode == .atmosphere ? .imagine : .outside)
        refreshUpcoming()
        apply()
        if mode == .atmosphere { applyWeather(to: .atmosphere, animated: false) }
        setUpSystemAudio()
        startClock()
        PlayPauseIntent.handler = { [weak self] in self?.togglePlayback() }
        if imagined {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.announce("Travel always plays a place's real weather now. For weather of your own, try Imagine.", for: 6)
            }
        }
    }

    // MARK: Lock screen, interruptions, route changes

    @ObservationIgnored private var resumeAfterInterruption = false

    private func setUpSystemAudio() {
        #if os(iOS)
        // No system Now Playing panel: the Live Activity is the lock-screen control.
        // (Registering remote commands or Now Playing info makes iOS show its own panel too.)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                resumeAfterInterruption = isPlaying
                if isPlaying { stop() }
            case .ended:
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                if resumeAfterInterruption && options.contains(.shouldResume) { play() }
                resumeAfterInterruption = false
            @unknown default: break
            }
        }
        // Pulling out headphones shouldn't suddenly play through the speaker.
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable,
                  isPlaying else { return }
            stop()
        }
        #endif
    }

    // MARK: Widget and Live Activity

    #if os(iOS)
    @ObservationIgnored private var activity: Activity<SoundscapeActivity>?
    #endif
    @ObservationIgnored private var lastSnapshot: NowPlayingSnapshot?
    @ObservationIgnored private var lastSnapshotSave = Date.distantPast

    /// Shares what's playing with the widget, and keeps the Live Activity in step.
    private func publishToWidgets() {
        // Away, the title is the place's name, so show its weather as the title instead.
        let conditions = mode == .escape ? escape?.conditions : mode == .atmosphere ? atmosphereConditions : home
        let displayTitle = (title == weather.place || title == escape?.place.name) ? (conditions?.mixName ?? title) : title
        let snapshot = NowPlayingSnapshot(
            title: displayTitle, place: weather.place, temperature: weather.temp, isPlaying: isPlaying,
            lights: byVolume.prefix(4).map { .init(hue: $0.kind.hue, chroma: $0.kind == .grey ? 0.1 : 1, volume: $0.volume) })
        guard snapshot != lastSnapshot else { return }
        let changedForWidget = snapshot.title != lastSnapshot?.title || snapshot.isPlaying != lastSnapshot?.isPlaying
            || snapshot.place != lastSnapshot?.place
        // Volume-only changes (a glide, a drag) are saved at most once a second.
        guard changedForWidget || Date().timeIntervalSince(lastSnapshotSave) > 1 else { return }
        lastSnapshotSave = Date()
        lastSnapshot = snapshot
        #if os(macOS)
        if changedForWidget { showInNowPlaying(snapshot) }
        #else
        snapshot.save()
        if changedForWidget { WidgetCenter.shared.reloadAllTimelines() }

        let placeLine = snapshot.temperature.isEmpty ? snapshot.place : "\(snapshot.place) \(snapshot.temperature)"
        let state = SoundscapeActivity.ContentState(title: snapshot.title, place: placeLine,
                                                    isPlaying: isPlaying, hues: snapshot.lights.map(\.hue))
        if isPlaying, activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(attributes: SoundscapeActivity(),
                                             content: .init(state: state, staleDate: nil))
        } else if let activity, changedForWidget {
            Task { await activity.update(.init(state: state, staleDate: nil)) }
        }
        #endif
    }

    #if os(iOS)
    /// Ends any Live Activity left from an earlier version.
    private func endAllActivities() {
        guard !Activity<SoundscapeActivity>.activities.isEmpty else { return }
        Task { for a in Activity<SoundscapeActivity>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }

    /// Ends the Live Activity a little after pausing, so a quick pause/play doesn't flicker it.
    private func endActivitySoon() {
        let current = activity
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !self.isPlaying, self.activity === current else { return }
            await current?.end(nil, dismissalPolicy: .immediate)
            self.activity = nil
        }
    }
    #endif

    #if os(macOS)
    // MARK: Now Playing on the Mac

    /// Set once something has played here. Until then the media keys and Now Playing stay with
    /// whatever app had them: just opening this one shouldn't take them.
    @ObservationIgnored private var hasPlayed = false
    @ObservationIgnored private var artwork: (hues: [Double], image: MPMediaItemArtwork)?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    /// The Mac has no Live Activity: the system's Now Playing (Control Center, the media keys,
    /// AirPods) shows and controls what's playing, and the forward and back keys travel.
    private func setUpRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayback(); return .success }
        commands.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        commands.pauseCommand.addTarget { [weak self] _ in self?.stop(); return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.requestTravel(forward: true); return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.requestTravel(forward: false); return .success }
    }

    private func showInNowPlaying(_ snapshot: NowPlayingSnapshot) {
        guard hasPlayed else { return }
        let hues = snapshot.lights.map(\.hue)
        if artwork?.hues != hues {
            // Drawing the halo is slow, so it waits until a slide to the new place has settled.
            artworkTask?.cancel()
            artworkTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.8))
                guard let self, !Task.isCancelled else { return }
                let halo = HaloArt(lights: snapshot.lights).frame(width: 320, height: 320).background(Theme.background)
                let renderer = ImageRenderer(content: halo)
                renderer.scale = 2
                guard let image = renderer.nsImage else { return }
                self.artwork = (hues, MPMediaItemArtwork(boundsSize: image.size) { _ in image })
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = self.artwork?.image
            }
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: snapshot.temperature.isEmpty ? snapshot.place : "\(snapshot.place) \(snapshot.temperature)",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork.image }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = snapshot.isPlaying ? .playing : .paused
    }
    #endif

    private func updateNowPlaying() {
        publishToWidgets()
    }

    // MARK: Reading

    var orbs: [Orb] { fields[mode] ?? [] }
    var title: String { titles[mode] ?? "" }
    var weather: WeatherSummary {
        if let preset = activePreset {
            let line = preset.description + (currentPlaceIsTweaked ? " · tuned by you" : "")
            return WeatherSummary(place: "Library", temp: "", line: line, head: preset.isSaved ? "Yours" : "Library mix")
        }
        switch mode {
        case .match:
            let head = "Here"
            switch weatherState {
            case .loading where home == nil:
                return WeatherSummary(place: "", temp: "", line: "Checking the weather…", head: head)
            case .locationOff:
                return WeatherSummary(place: "Location off", temp: "",
                                      line: "Allow location in Settings to match outside", head: "Here")
            case .failed where home == nil:
                return WeatherSummary(place: "Offline", temp: "", line: "Couldn't reach the weather · a quiet mix till then", head: head)
            default:
                guard let home else { return WeatherSummary(place: "", temp: "", line: "", head: head) }
                let line = following[.match] == true
                    ? "\(home.sceneDescription.capitalizedFirst) outside" + (tweaks["home"] != nil ? " · tuned by you" : "")
                    : "Your own mix, made here"
                return WeatherSummary(place: home.place, temp: home.temperature, line: line, head: head)
            }
        case .escape:
            guard let escape else {
                if let pinned = pinnedPlace {
                    return WeatherSummary(place: pinned.title, temp: "", line: "Checking the weather in \(pinned.name)…",
                                          head: "Live in \(pinned.name)")
                }
                return WeatherSummary(place: "", temp: "", line: "Finding somewhere else…", head: "Places")
            }
            let c = escape.conditions
            let line: String
            if following[.escape] != true {
                line = "Your own mix, made in \(escape.place.name)"
            } else if pinnedPlace != nil {
                line = "\(c.sceneDescription.capitalizedFirst) in \(escape.place.name)"
                    + (tweaks[escape.place.name] != nil ? " · tuned by you" : "")
            } else {
                line = Self.escapeLine(c)
            }
            return WeatherSummary(place: escape.place.title, temp: c.temperature, line: line,
                                  head: "Live in \(escape.place.name)")
        case .atmosphere:
            guard let a = atmosphere else { return WeatherSummary(place: "", temp: "", line: "", head: "Atmosphere") }
            let line = following[.atmosphere] != true ? "Your own mix, made from \(a.setting.info.name.lowercased())"
                : a.setting.info.line + (tweaks[a.tweakKey] != nil ? " · tuned by you" : "")
            return WeatherSummary(place: a.setting.info.name, temp: "", line: line, head: "Atmosphere")
        case .mix:
            // A mix that's gone (its saved copy deleted): what's left of it.
            return WeatherSummary(place: "", temp: "", line: "", head: "Yours")
        }
    }

    // MARK: Atmospheres

    /// The atmosphere playing in Atmosphere mode.
    private(set) var atmosphere: Atmosphere?

    /// The atmosphere's weather: its own, in its season, on your clock.
    var atmosphereConditions: Conditions? { atmosphere?.imagined() }

    /// The title as the page shows it: an atmosphere's name over two lines.
    var titleLines: [String] {
        guard activePreset == nil, mode == .atmosphere, let a = atmosphere, let c = atmosphereConditions,
              title == a.title(in: c) else { return [title] }
        return a.lines(in: c)
    }

    /// Goes to an atmosphere, gliding there, and plays it unless told not to.
    func go(to atmosphere: Atmosphere, play shouldPlay: Bool = true) {
        setActivePreset(nil)
        self.atmosphere = atmosphere
        if let data = try? JSONEncoder().encode(atmosphere) { defaults.set(data, forKey: "atmosphere") }
        traveling = true
        if mode != .atmosphere {
            transition?.cancel()
            // Start from what's playing, so the sound crossfades into the scene.
            fields[.atmosphere] = visualTarget ?? orbs
            mode = .atmosphere
            defaults.set(Mode.atmosphere.rawValue, forKey: "mode")
        }
        setFollowing(true, for: .atmosphere)
        applyWeather(to: .atmosphere, animated: true)
        updateNowPlaying()
        if shouldPlay && !isPlaying { play() }
        arrived()
        lensFollows(.imagine)
    }

    /// Goes to a scene described in words, its sounds changed as asked. The changes are kept as
    /// the scene's tweaks, as if made in Layers, so Reset puts it back. A scene described anew is
    /// as described, whatever it was tuned to before; words that only refine it add to that.
    func go(to vibe: Vibe) {
        let a = vibe.atmosphere
        let changes = vibe.tweaks(over: a.mix(in: a.imagined()))
        if vibe.refines {
            tweaks[a.tweakKey, default: [:]].merge(changes) { $1 }
        } else {
            tweaks[a.tweakKey] = changes.isEmpty ? nil : changes
        }
        persistTweaks()
        go(to: a)
        if let said = vibe.summary { announce(said, for: 3.5) }
    }

    /// The same setting in other weather: swipe down, or the Weather menu.
    func setAtmosphereSky(_ sky: Sky) {
        guard let a = atmosphere, a.sky != sky else { return }
        go(to: Atmosphere(a.setting, sky, a.time), play: false)
    }

    func cycleAtmosphereSky() {
        guard let a = atmosphere else { return }
        let skies = a.setting.info.skies
        setAtmosphereSky(skies[((skies.firstIndex(of: a.sky) ?? 0) + 1) % skies.count])
    }

    func setAtmosphereTime(_ time: TimeOfDay) {
        guard let a = atmosphere, a.time != time else { return }
        go(to: Atmosphere(a.setting, a.sky, time), play: false)
    }

    private static func escapeLine(_ c: Conditions) -> String {
        let feel = c.temperatureC >= 20 ? "warm" : c.temperatureC <= 8 ? "cold" : "mild"
        if c.isThunder { return "Somewhere stormy" }
        if c.isSnow { return "Somewhere snowing" }
        if c.isRaining { return "Somewhere rainy and \(feel)" }
        if c.windKMH > 30 { return "Somewhere wild and windy" }
        return "Somewhere dry and \(feel)"
    }

    /// Orbs loudest first.
    /// What the halo shows. While traveling it shows the destination right away (it's what slid in),
    /// even though the sound is still crossfading.
    var byVolume: [Orb] { (visualTarget ?? orbs).sorted { $0.volume > $1.volume } }

    var unusedSounds: [SoundKind] {
        let used = Set(orbs.map(\.kind))
        return SoundKind.available.filter { !used.contains($0) }
    }

    // MARK: Editing the field

    /// Switches modes. Choosing the mode you're already in hands the field back to the weather.
    func setMode(_ newMode: Mode) {
        if newMode == mode {
            setFollowing(true, for: mode)
            applyWeather(to: mode, animated: true)
            return
        }
        transition?.cancel()
        mode = newMode
        defaults.set(newMode.rawValue, forKey: "mode")
        apply()
        updateNowPlaying()
    }

    /// Moves an orb, keeping it inside the circle.
    func move(_ id: Orb.ID, toX x: Double, y: Double) {
        transition?.cancel()
        visualTarget = nil
        var x = x, y = y
        let d = hypot(x - 0.5, y - 0.5)
        if d > 0.5 {
            x = 0.5 + (x - 0.5) / d * 0.5
            y = 0.5 + (y - 0.5) / d * 0.5
        }
        update(id) { $0.x = x; $0.y = y }
    }

    /// Nudges a sound louder (positive) or quieter (negative). Used by VoiceOver.
    func adjustVolume(_ id: Orb.ID, by delta: Double) {
        guard let orb = orbs.first(where: { $0.id == id }) else { return }
        setVolume(id, to: orb.volume + delta)
    }

    /// Sets how loud a sound is, keeping which way it is from you (and so its spoke in the shape).
    func setVolume(_ id: Orb.ID, to volume: Double) {
        guard let orb = orbs.first(where: { $0.id == id }) else { return }
        transition?.cancel()
        visualTarget = nil
        let target = max(0, min(0.995, volume))
        let dx = orb.x - 0.5, dy = orb.y - 0.5
        let d = hypot(dx, dy)
        let (ux, uy) = d < 0.001 ? (0.0, 1.0) : (dx / d, dy / d)
        let r = (1 - target) * 0.5
        update(id) { $0.x = 0.5 + ux * r; $0.y = 0.5 + uy * r }
    }

    // MARK: Pace

    /// How often a sound that comes and goes comes, wherever it plays: thunder rarely for a calm
    /// night, constantly for a storm to get lost in.
    enum Pace: String, CaseIterable {
        case rarely = "Rarely", sometimes = "Now and then", often = "Often", constantly = "Constantly"

        var rate: Double {
            switch self {
            case .rarely: 0.4
            case .sometimes: 1
            case .often: 2
            case .constantly: 4
            }
        }
    }

    private(set) var paces: [SoundKind: Pace] = [:]

    func pace(of kind: SoundKind) -> Pace { paces[kind] ?? .sometimes }

    /// The next pace round, for a tap.
    func cyclePace(of kind: SoundKind) {
        let all = Pace.allCases
        let next = all[((all.firstIndex(of: pace(of: kind)) ?? 1) + 1) % all.count]
        paces[kind] = next == .sometimes ? nil : next
        engine.setPace(next.rate, for: kind)
        defaults.set(Dictionary(uniqueKeysWithValues: paces.map { ($0.key.rawValue, $0.value.rawValue) }), forKey: "paces")
    }

    func remove(_ id: Orb.ID) {
        fields[mode]?.removeAll { $0.id == id }
        markCustom()
        apply()
    }

    /// Brings in a sound at `level`, somewhere around the field, and says so.
    func add(_ kind: SoundKind, level: Double = 0.5) {
        let angle = Double.random(in: 0..<(2 * .pi))
        let r = (1 - level) * 0.5
        fields[mode, default: []].append(Orb(kind: kind, x: 0.5 + cos(angle) * r, y: 0.5 + sin(angle) * r))
        markCustom()
        apply()
        announce("\(kind.short) joins \(currentPlaceName)", for: 1.6)
    }

    /// Takes every layer of a sound away, and says so.
    func removeAll(_ kind: SoundKind) {
        fields[mode]?.removeAll { $0.kind == kind }
        markCustom()
        apply()
        announce("\(kind.short) leaves \(currentPlaceName)", for: 1.6)
    }

    /// A Library mix that's playing. It stands on its own, apart from any place's weather.
    private(set) var activePreset: Preset?

    // MARK: Saved mixes

    private(set) var savedMixes: [SavedMix] = []

    /// A name to start from when saving, e.g. "Waterford, light rain".
    var suggestedSaveName: String {
        if let p = activePreset { return p.isSaved ? "\(p.name), again" : "\(p.name), my way" }
        if mode == .escape, let e = escape { return "\(e.place.title), my way" }
        if mode == .atmosphere, atmosphere != nil { return "\(title), my way" }
        if let h = home { return "\(h.place), my way" }
        return title
    }

    private var saveOrigin: String {
        let date = Date().formatted(.dateTime.month(.abbreviated).day())
        if let p = activePreset { return "From \(p.name), \(date)" }
        if mode == .escape, let e = escape { return "Saved from \(e.place.name)'s \(e.conditions.mixName.lowercased()), \(date)" }
        if mode == .atmosphere, atmosphere != nil { return "Saved from \(title.prefix(1).lowercased() + title.dropFirst()), \(date)" }
        if let h = home { return "Saved from \(h.mixName.lowercased()) in \(h.place), \(date)" }
        return "Saved \(date)"
    }

    /// Saves the field exactly as it is now and makes it the playing mix.
    func saveCurrent(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mix = SavedMix(name: trimmed.isEmpty ? suggestedSaveName : trimmed, origin: saveOrigin,
                           orbs: (visualTarget ?? orbs).filter { $0.volume > 0.01 })
        savedMixes.insert(mix, at: 0)
        persistSaved()
        setActivePreset(mix.preset)
        enterMix(mix.preset.orbs, title: mix.name)
    }

    /// Plays `orbs` in the mix's own field, leaving the place it came from as it was.
    private func enterMix(_ orbs: [Orb], title: String) {
        transition?.cancel()
        visualTarget = nil
        fields[.mix] = orbs
        setTitle(title, for: .mix)
        if mode != .mix {
            mode = .mix
            defaults.set(Mode.mix.rawValue, forKey: "mode")
        }
        apply()
        updateNowPlaying()
    }

    func rename(_ mix: SavedMix, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = savedMixes.firstIndex(of: mix) else { return }
        savedMixes[i].name = trimmed
        persistSaved()
        if activePreset?.savedID == mix.id {
            setActivePreset(savedMixes[i].preset)
            setTitle(trimmed, for: .mix)
        }
    }

    func delete(_ mix: SavedMix) {
        savedMixes.removeAll { $0.id == mix.id }
        persistSaved()
        if isFavorite(Self.favoriteKey(mix.preset)) { toggleFavorite(Self.favoriteKey(mix.preset)) }
        tweaks[Self.tweakKey(mix.preset)] = nil
        persistTweaks()
        if activePreset?.savedID == mix.id { leaveMix() }
    }

    /// Out of a mix, back to the last real place, playing or paused as it was.
    private func leaveMix() {
        if let p = pinnedPlace { select(p, play: false) } else { goHome() }
    }

    // MARK: Favorites

    /// What you've marked as a favorite, newest first: Library mixes (`mix:` and the mix's ID) and
    /// scenes (`scene:` and the atmosphere's ID). Kept on this device.
    private(set) var favorites: [String] = UserDefaults.standard.stringArray(forKey: "favorites") ?? []

    func isFavorite(_ key: String) -> Bool { favorites.contains(key) }

    func toggleFavorite(_ key: String) {
        if let i = favorites.firstIndex(of: key) {
            favorites.remove(at: i)
            announce("Taken out of Yours")
        } else {
            favorites.insert(key, at: 0)
            announce("Saved to Yours, in the Library")
        }
        defaults.set(favorites, forKey: "favorites")
    }

    /// A word on what you just did ("Added to Favorites…"), shown for a moment where the hints appear.
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    func announce(_ text: String, for seconds: Double = 2.5) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    nonisolated static func favoriteKey(_ preset: Preset) -> String { "mix:\(preset.id)" }
    nonisolated static func favoriteKey(_ atmosphere: Atmosphere) -> String { "scene:\(atmosphere.id)" }
    /// The same as a visit to it is kept (`Visit`).
    nonisolated static func favoriteKey(_ place: Place) -> String { "place:\(place.name)" }

    /// What's playing, as something to favorite: a Library mix, a scene or a real place (not
    /// your own weather, always first among places).
    var favoriteKey: String? {
        if let p = activePreset { return Self.favoriteKey(p) }
        if mode == .atmosphere, let a = atmosphere { return Self.favoriteKey(a) }
        if mode == .escape, let p = escape?.place { return Self.favoriteKey(p) }
        return nil
    }

    enum Favorite: Identifiable {
        case scene(Atmosphere), mix(Preset), place(Place)
        var id: String {
            switch self {
            case .scene(let a): Mixer.favoriteKey(a)
            case .mix(let p): Mixer.favoriteKey(p)
            case .place(let p): Mixer.favoriteKey(p)
            }
        }
    }

    /// Your favorites, newest first, as things to play.
    var favoriteItems: [Favorite] {
        let mixes = savedMixes.map(\.preset) + Preset.all
        return favorites.compactMap { key in
            if key.hasPrefix("scene:"), let a = Atmosphere(id: String(key.dropFirst(6))) { return .scene(a) }
            if key.hasPrefix("mix:"), let p = mixes.first(where: { Self.favoriteKey($0) == key }) { return .mix(p) }
            if key.hasPrefix("place:"), let p = allPlaces.first(where: { Self.favoriteKey($0) == key }) { return .place(p) }
            return nil
        }
    }

    // MARK: Recent

    /// Somewhere you've been, and when you were last there.
    struct Visit: Codable, Equatable, Identifiable {
        /// As a favorite is kept (`scene:` and the atmosphere's ID, `mix:` and the mix's ID), or
        /// `place:` and the name of a real place.
        let key: String
        var at: Date
        var id: String { key }
    }

    /// Where you've been, newest first, each once: the last 20 scenes, places and Library mixes you
    /// stayed in for a few seconds, so ones swiped straight past aren't kept. Kept on this device.
    private(set) var recent: [Visit] = UserDefaults.standard.data(forKey: "recent")
        .flatMap { try? JSONDecoder().decode([Visit].self, from: $0) } ?? []
    @ObservationIgnored private var visiting: Task<Void, Never>?

    /// Arrived somewhere: kept as a visit if you're still there in a few seconds.
    private func arrived() {
        visiting?.cancel()
        visiting = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.noteVisit()
        }
    }

    private func noteVisit() {
        let key: String
        if let p = activePreset {
            key = Self.favoriteKey(p)
        } else if mode == .atmosphere, let a = atmosphere {
            key = Self.favoriteKey(a)
        } else if mode == .escape, let p = escape?.place {
            key = "place:\(p.name)"
        } else {
            return   // your own weather is always a tap away
        }
        // The same scene in other weather carries on the visit rather than adding another.
        if let last = recent.first, last.key != key, Self.setting(of: last.key) != nil,
           Self.setting(of: last.key) == Self.setting(of: key) {
            recent.removeFirst()
        }
        recent.removeAll { $0.key == key }
        recent.insert(Visit(key: key, at: Date()), at: 0)
        recent = Array(recent.prefix(20))
        if let data = try? JSONEncoder().encode(recent) { defaults.set(data, forKey: "recent") }
    }

    /// The setting of a scene's key: `cabin` in `scene:cabin.snow.night`.
    private static func setting(of key: String) -> Substring? {
        key.hasPrefix("scene:") ? key.dropFirst(6).split(separator: ".").first : nil
    }

    func clearRecent() {
        recent = []
        defaults.removeObject(forKey: "recent")
    }

    /// Somewhere to go back to.
    enum Revisit {
        case scene(Atmosphere), mix(Preset), place(Place)
    }

    /// Where you've been, newest first, as places to go back to.
    var recentItems: [(visit: Visit, item: Revisit)] {
        let mixes = savedMixes.map(\.preset) + Preset.all
        return recent.compactMap { v in
            if v.key.hasPrefix("scene:"), let a = Atmosphere(id: String(v.key.dropFirst(6))) { return (v, .scene(a)) }
            if v.key.hasPrefix("mix:"), let p = mixes.first(where: { Self.favoriteKey($0) == v.key }) { return (v, .mix(p)) }
            if v.key.hasPrefix("place:"), let p = allPlaces.first(where: { "place:\($0.name)" == v.key }) { return (v, .place(p)) }
            return nil
        }
    }

    /// Goes back to somewhere you've been.
    func revisit(_ item: Revisit) {
        switch item {
        case .scene(let a): go(to: a)
        case .mix(let p): load(p)
        case .place(let p): select(p)
        }
    }

    // MARK: Yours

    /// Everything you've kept, as one list: your own mixes (saved as new) and the places, scenes
    /// and mixes you bookmarked.
    enum YoursItem: Identifiable {
        case saved(SavedMix), kept(Favorite)
        var id: String {
            switch self {
            case .saved(let m): "saved:\(m.id.uuidString)"
            case .kept(let f): f.id
            }
        }
    }

    /// Yours in your own order; anything kept since it was last arranged comes first.
    private(set) var yoursOrder: [String] = UserDefaults.standard.stringArray(forKey: "yoursOrder") ?? []

    var yoursItems: [YoursItem] {
        var all: [String: YoursItem] = [:]
        var newest: [String] = []
        for m in savedMixes {
            let item = YoursItem.saved(m)
            all[item.id] = item
            newest.append(item.id)
        }
        // A bookmark on one of your own mixes is the mix itself.
        for f in favoriteItems {
            if case .mix(let p) = f, p.isSaved { continue }
            all[f.id] = .kept(f)
            newest.append(f.id)
        }
        let arranged = yoursOrder.filter { all[$0] != nil }
        let fresh = newest.filter { !arranged.contains($0) }
        return (fresh + arranged).compactMap { all[$0] }
    }

    func moveYours(from source: IndexSet, to destination: Int) {
        var ids = yoursItems.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        yoursOrder = ids
        defaults.set(ids, forKey: "yoursOrder")
    }

    /// Takes something out of Yours: one of your own mixes is deleted, a bookmark lifted.
    func removeFromYours(_ item: YoursItem) {
        switch item {
        case .saved(let m): delete(m)
        case .kept(let f): if isFavorite(f.id) { toggleFavorite(f.id) }
        }
    }

    /// Where you are, chosen: its weather, playing.
    func playHere() {
        goHome()
        if !isPlaying { play() }
    }

    private func persistSaved() {
        if let data = try? JSONEncoder().encode(savedMixes) { defaults.set(data, forKey: "savedMixes") }
    }

    private func setActivePreset(_ preset: Preset?) {
        activePreset = preset
        defaults.set(preset?.id, forKey: "activePreset")
    }

    /// Your own weather, for the corner: "Seekonk 65°" (as it really is, whatever you're imagining).
    var outsideLabel: String {
        if let h = liveHome { return "\(h.place) \(h.temperature)" }
        switch weatherState {
        case .locationOff: return "Location off"
        case .failed: return "Offline"
        default: return "Outside"
        }
    }

    /// A real place's weather, as Tune shows it: "Live · A clear autumn night · 63°". Nil for a
    /// scene or a mix.
    var liveLine: String? {
        let c: Conditions? = switch mode {
        case .match: home
        case .escape: escape?.conditions
        case .atmosphere, .mix: nil
        }
        return c.map { "Live · \($0.sceneDescription.capitalizedFirst) · \($0.temperature)" }
    }

    /// A symbol for the weather outside, beside it.
    var outsideSymbol: String { liveHome?.symbol ?? "location" }

    /// Whether there's a place to go back to: something other than a place is playing.
    var awayFromPlaces: Bool { activePreset != nil || mode == .atmosphere }
    /// The real place you were last in (`pinnedPlace`, nil for where you are): where Back to … and
    /// the wheel's Places go.
    var lastPlaceName: String { pinnedPlace?.name ?? homeName }

    /// Back to the last real place, from a mix or a scene, playing it: a choice, not a browse.
    func backToPlace() {
        if let p = pinnedPlace { select(p) } else { goHome(); if !isPlaying { play() } }
    }

    /// Turns the wheel a stop on or back, as ↑ ↓ do on a Mac.
    func turnWheel(forward: Bool) {
        let all = Lens.allCases
        guard let lens else { return choose(forward ? all[0] : all[all.count - 1]) }
        let i = all.firstIndex(of: lens) ?? 0
        choose(all[(i + (forward ? 1 : -1) + all.count) % all.count])
    }

    /// Plays a mix in its own field, as you last tuned it, leaving the place you were in as it was.
    func load(_ preset: Preset, play shouldPlay: Bool = true) {
        setActivePreset(preset)
        let tuned = tweaks[Self.tweakKey(preset)]
        enterMix(tuned == nil ? preset.orbs : Preset.layout(Self.applying(tuned, to: preset.mix)), title: preset.name)
        if shouldPlay && !isPlaying { play() }
        arrived()
        if let tag = preset.tag {
            defaults.set(preset.id, forKey: "lens.\(Lens(tag).rawValue)")
            lensFollows(Lens(tag))
        } else {
            lensFollows(nil)
        }
    }

    private func update(_ id: Orb.ID, _ change: (inout Orb) -> Void) {
        guard let i = fields[mode]?.firstIndex(where: { $0.id == id }) else { return }
        change(&fields[mode]![i])
        markCustom()
        apply()
    }

    /// An edit stays with what was edited, a place, a scene or a mix, as a lasting tweak to it
    /// that Reset takes back. Nothing breaks away into a mix of its own unless saved as new.
    private func markCustom() {
        if let key = tweakKey { recordTweaks(for: key) }
    }

    // MARK: Per-place tweaks

    /// Volume changes you've made to a place, by sound: added on top of what the weather gives.
    private(set) var tweaks: [String: [String: Double]] = [:]

    /// What the field belongs to right now, for its tweaks: "home", a place's name, a scene's key,
    /// or a mix's ("mix:" and its ID; "saved:" and its UUID for one of yours, so renaming keeps them).
    private var tweakKey: String? {
        if let p = activePreset { return Self.tweakKey(p) }
        switch mode {
        case .escape: return escape?.place.name
        case .atmosphere: return atmosphere?.tweakKey
        case .match: return "home"
        case .mix: return nil
        }
    }

    nonisolated static func tweakKey(_ preset: Preset) -> String {
        preset.savedID.map { "saved:\($0.uuidString)" } ?? favoriteKey(preset)
    }

    var currentPlaceIsTweaked: Bool { tweakKey.map { !(tweaks[$0] ?? [:]).isEmpty } ?? false }

    /// The sounds that belong to where you are, to suggest first in Layers.
    var currentCast: [SoundKind] {
        guard activePreset == nil else { return [] }
        let place = mode == .escape ? escape?.place : mode == .atmosphere ? atmosphere?.setting.place : homePlace
        var seen = Set<SoundKind>()
        return (place?.signature.compactMap { $0.0.playable } ?? []).filter { seen.insert($0).inserted }
    }

    /// Where those sounds are from, e.g. "Lisbon".
    var currentCastPlace: String? {
        guard activePreset == nil else { return nil }
        if mode == .atmosphere { return atmosphere?.setting.info.name }
        return mode == .escape ? escape?.place.name : home?.place
    }
    var currentPlaceName: String {
        switch mode {
        case .escape: escape?.place.name ?? "this place"
        case .atmosphere: "this scene"
        case .match: home?.place ?? "home"
        case .mix: activePreset?.name ?? "this mix"
        }
    }

    /// What the weather alone gives this mode, before tweaks (for a mix, the mix as made).
    private func baseMix(for mode: Mode) -> [(SoundKind, Double)]? {
        switch mode {
        case .mix: return activePreset?.mix
        case .match: return home.map { WeatherMix.orbs(for: $0, place: homePlace) }
        case .escape: return escape.map { WeatherMix.orbs(for: $0.conditions, place: $0.place) }
        case .atmosphere: return atmosphere.flatMap { a in atmosphereConditions.map { a.mix(in: $0) } }
        }
    }

    /// Stores the difference between the field and the weather mix as this place's tweaks.
    private func recordTweaks(for key: String) {
        guard let base = baseMix(for: mode) else { return }
        var baseLevels: [SoundKind: Double] = [:]
        for (k, v) in base { baseLevels[k] = v }
        var delta: [String: Double] = [:]
        var fieldLevels: [SoundKind: Double] = [:]
        for o in orbs { fieldLevels[o.kind] = max(fieldLevels[o.kind] ?? 0, o.volume) }
        for k in Set(baseLevels.keys).union(fieldLevels.keys) {
            let d = (fieldLevels[k] ?? 0) - (baseLevels[k] ?? 0)
            if abs(d) > 0.02 { delta[k.rawValue] = d }
        }
        tweaks[key] = delta.isEmpty ? nil : delta
        persistTweaks()
    }

    static func applying(_ delta: [String: Double]?, to base: [(SoundKind, Double)]) -> [(SoundKind, Double)] {
        guard let delta, !delta.isEmpty else { return base }
        var out: [(SoundKind, Double)] = base.map { k, v in (k, min(1, max(0, v + (delta[k.rawValue] ?? 0)))) }
        for (raw, d) in delta {
            guard let k = SoundKind(rawValue: raw), !base.contains(where: { $0.0 == k }), d > 0 else { continue }
            out.append((k, min(1, d)))
        }
        return out.filter { $0.1 >= 0.03 }
    }

    /// Puts what's playing back to how it sounds by default: a place or scene following its
    /// weather, a mix as it was made.
    func resetCurrentPlace() {
        if let key = tweakKey {
            tweaks[key] = nil
            persistTweaks()
        }
        if mode == .mix, let p = activePreset {
            glide(to: p.orbs, duration: 1.5)
            return
        }
        traveling = true
        applyWeather(to: mode, animated: true)
    }

    /// Once, for fields from before each kind had its own: a Library mix played in a place's field
    /// moves to the mix's, and a field that broke away as "Your mix" is kept in Yours, the place
    /// going back to following its weather.
    private func migrateToOwnSlots() {
        guard defaults.integer(forKey: "migratedIA") < 1 else { return }
        defaults.set(1, forKey: "migratedIA")
        if let p = activePreset, mode != .mix {
            fields[.mix] = fields[mode]
            titles[.mix] = p.name
            defaults.set(p.name, forKey: "title.mix")
            following[mode] = true
            defaults.set(true, forKey: "following.\(mode.rawValue)")
            mode = .mix
            defaults.set(Mode.mix.rawValue, forKey: "mode")
        }
        var kept = 0
        for m in [Mode.match, .escape, .atmosphere] where titles[m] == "Your mix" || following[m] == false {
            let orbs = (fields[m] ?? []).filter { $0.volume > 0.01 }
            if !orbs.isEmpty {
                kept += 1
                let mix = SavedMix(name: kept == 1 ? "Your mix (kept)" : "Your mix (kept) \(kept)",
                                   origin: "Kept from before, \(Date().formatted(.dateTime.month(.abbreviated).day()))",
                                   orbs: orbs)
                savedMixes.insert(mix, at: 0)
                if m == mode {
                    activePreset = mix.preset
                    defaults.set(mix.preset.id, forKey: "activePreset")
                    fields[.mix] = orbs
                    titles[.mix] = mix.name
                    defaults.set(mix.name, forKey: "title.mix")
                    mode = .mix
                    defaults.set(Mode.mix.rawValue, forKey: "mode")
                }
            }
            titles[m] = ""
            defaults.set("", forKey: "title.\(m.rawValue)")
            following[m] = true
            defaults.set(true, forKey: "following.\(m.rawValue)")
        }
        if kept > 0 { persistSaved() }
    }

    private func persistTweaks() { defaults.set(tweaks, forKey: "placeTweaks") }

    private func setTitle(_ title: String, for mode: Mode) {
        titles[mode] = title
        defaults.set(title, forKey: "title.\(mode.rawValue)")
        if mode == self.mode { updateNowPlaying() }
    }

    private func setFollowing(_ value: Bool, for mode: Mode) {
        following[mode] = value
        defaults.set(value, forKey: "following.\(mode.rawValue)")
    }

    // MARK: Weather

    /// Fetches home and escape weather, then updates any field that's following it.
    /// Skips the network if the last fetch was recent, unless forced.
    func refreshWeather(force: Bool = false) async {
        if !force, let last = lastWeatherFetch, Date().timeIntervalSince(last) < 20 * 60 { return }
        lastWeatherFetch = Date()
        if home == nil { weatherState = .loading }

        // Places first: they don't depend on where you are.
        let places = allPlaces
        async let placeWeather = try? weatherService.conditions(for: places)

        do {
            let (coordinate, place) = try await location.current()
            homeCoordinate = coordinate
            liveHome = try await weatherService.conditions(at: coordinate, place: place)
            await resolveHomePlace(coordinate, name: place)
            weatherState = .ready
        } catch {
            weatherState = location.isDenied ? .locationOff : .failed
            if liveHome == nil { hereWithoutWeather() }
        }

        if let options = await placeWeather {
            livePlaceConditions = Dictionary(zip(places.map(\.name), options), uniquingKeysWith: { a, _ in a })
            chooseEscape()
        } else {
            // Don't wait 20 minutes for the next try if places didn't load.
            lastWeatherFetch = nil
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                await self?.refreshWeather()
            }
        }

        applyWeather(to: .match, animated: true)
        applyWeather(to: .escape, animated: true)
        applyWeather(to: .atmosphere, animated: true)
    }

    /// Where you are with no weather to go on (no location, or offline): named as Here, never a
    /// name left over from before, and never silent: a quiet mix till the weather comes.
    private func hereWithoutWeather() {
        setTitle("Here", for: .match)
        if (fields[.match] ?? []).isEmpty {
            fields[.match] = Preset.layout([(.breeze, 0.45), (.birds, 0.25), (.pink, 0.3)])
            if mode == .match { apply() }
        }
    }

    // MARK: Home's character

    /// Home, as a place: what can be heard there through the year.
    @ObservationIgnored private var homePlace: Place?

    /// Near one of our places, home borrows its character; anywhere else, it listens to what's
    /// around (coast, lakes, woods, a city). Cached so it only looks again after a move.
    private func resolveHomePlace(_ c: CLLocationCoordinate2D, name: String) async {
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        func distance(_ p: Place) -> Double { here.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude)) }
        if let near = Place.all.min(by: { distance($0) < distance($1) }), distance(near) < 40_000 {
            homePlace = Place(name: name, country: near.country, region: .yours, latitude: c.latitude, longitude: c.longitude,
                              signature: near.signature, climate: near.climate, wetMonths: near.wetMonths, seasonal: near.seasonal)
            return
        }
        let key = String(format: "v2:%.1f,%.1f", c.latitude, c.longitude)   // about 10 km; v2 added traffic and planes
        if let saved = defaults.dictionary(forKey: "homeCast"), saved["key"] as? String == key,
           let dict = saved["place"] as? [String: Any], let place = Place(dictionary: dict) {
            homePlace = place
            return
        }
        let place = Place(name: name, country: "", region: .yours, latitude: c.latitude, longitude: c.longitude,
                          signature: await PlaceSearch.cast(near: c))
        homePlace = place
        defaults.set(["key": key, "place": place.dictionary], forKey: "homeCast")
    }

    // MARK: The clock

    /// Scenes follow the local clock as well as the weather: dawn brings the birds, the city
    /// quiets after midnight, bells ring on the hour. Checked every minute; changes glide in.
    @ObservationIgnored private var clock: Foundation.Timer?

    private func startClock() {
        clock = Foundation.Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.followClock() }
        }
    }

    private func followClock() {
        guard activePreset == nil, following[mode] == true, visualTarget == nil,
              let target = weatherTarget(for: mode) else { return }
        // "A rainy afternoon" becomes "a rainy evening" as the light goes.
        if mode == .atmosphere, let a = atmosphere, let c = atmosphereConditions, title != a.title(in: c) {
            applyWeather(to: mode, animated: true)
            return
        }
        var now: [SoundKind: Double] = [:]
        for o in orbs { now[o.kind] = max(now[o.kind] ?? 0, o.volume) }
        let changed = Set(now.keys).union(target.map(\.0)).contains { kind in
            abs((now[kind] ?? 0) - (target.first { $0.0 == kind }?.1 ?? 0)) > 0.03
        }
        if changed { applyWeather(to: mode, animated: true) }
    }

    /// What the weather and the clock make of a mode right now, with any tweaks.
    private func weatherTarget(for mode: Mode) -> [(SoundKind, Double)]? {
        switch mode {
        case .match:
            return home.map { Self.applying(tweaks["home"], to: WeatherMix.orbs(for: $0, place: homePlace)) }
        case .escape:
            return escape.map { Self.applying(tweaks[$0.place.name], to: WeatherMix.orbs(for: $0.conditions, place: $0.place)) }
        case .atmosphere:
            guard let a = atmosphere, let c = atmosphereConditions else { return nil }
            return Self.applying(tweaks[a.tweakKey], to: a.mix(in: c))
        case .mix:
            return nil
        }
    }

    /// Uses the pinned place if there is one, otherwise the place least like home.
    private func chooseEscape() {
        if let pinned = pinnedPlace, let c = livePlaceConditions[pinned.name] {
            liveEscape = (pinned, c)
            return
        }
        let options = Place.all.compactMap { p in livePlaceConditions[p.name].map { (p, $0) } }   // curated places only
        guard !options.isEmpty else { return }
        let i = WeatherMix.bestEscape(from: liveHome, options: options.map(\.1))
        liveEscape = options[i]
    }

    /// Goes to a place: pins it, switches to Escape, and glides the field to its sound.
    func select(_ place: Place, play shouldPlay: Bool = true) {
        setActivePreset(nil)
        // Choosing the place you're already in is just going home.
        if isNearHome(place) {
            pinnedPlace = nil
            defaults.removeObject(forKey: "pinnedPlace")
            goHome()
            if shouldPlay && !isPlaying { play() }
            return
        }
        pinnedPlace = place
        defaults.set(place.name, forKey: "pinnedPlace")
        traveling = true
        chooseEscape()
        if mode != .escape {
            transition?.cancel()
            mode = .escape
            defaults.set(Mode.escape.rawValue, forKey: "mode")
        }
        setFollowing(true, for: .escape)
        applyWeather(to: .escape, animated: true)
        updateNowPlaying()
        if shouldPlay && !isPlaying { play() }
        arrived()
        lensFollows(.outside)
    }

    /// Comes back from a place to the local weather.
    func goHome() {
        setActivePreset(nil)
        traveling = true
        if mode != .match {
            transition?.cancel()
            mode = .match
            defaults.set(Mode.match.rawValue, forKey: "mode")
            apply()
        }
        setFollowing(true, for: .match)
        applyWeather(to: .match, animated: true)
        updateNowPlaying()
        // Where you are is the place you were last in now.
        pinnedPlace = nil
        defaults.removeObject(forKey: "pinnedPlace")
        lensFollows(.outside)
    }

    /// Hands an edited field back to the weather, without leaving the place.
    func followWeatherAgain() {
        setActivePreset(nil)
        setFollowing(true, for: mode)
        applyWeather(to: mode, animated: true)
    }

    /// Where home is on the map, to tell when a chosen place is really just home.
    @ObservationIgnored private var homeCoordinate: CLLocationCoordinate2D?

    /// Whether a place is where you are: anywhere within 15 km, or the curated place nearest to
    /// you within 40 km. (So from Providence, Newport is still a trip.)
    private func isNearHome(_ place: Place) -> Bool {
        guard let h = homeCoordinate else { return false }
        let here = CLLocation(latitude: h.latitude, longitude: h.longitude)
        func distance(_ p: Place) -> Double { here.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude)) }
        let d = distance(place)
        if d < 15_000 { return true }
        guard d < 40_000 else { return false }
        return Place.all.min(by: { distance($0) < distance($1) })?.name == place.name
    }

    /// Where "home" is, for the "Back to …" line.
    var homeName: String { home?.place ?? "home" }

    // MARK: Carousel

    enum Destination: Equatable {
        case home
        case place(Place)
        case atmosphere(Atmosphere)
        case preset(Preset)

        /// What marks it as a favorite, if it can be one: a scene or a mix can.
        var favoriteKey: String? {
            switch self {
            case .atmosphere(let a): Mixer.favoriteKey(a)
            case .preset(let p): Mixer.favoriteKey(p)
            default: nil
            }
        }
    }

    /// Where the field is now.
    var here: Destination {
        if let p = activePreset { return .preset(p) }
        if mode == .escape, let p = escape?.place { return .place(p) }
        if mode == .atmosphere, let a = atmosphere { return .atmosphere(a) }
        return .home
    }

    /// What the wheel at the top is turned to: what swiping goes through. Travel goes round where
    /// you are and the real places, westward, in their weather now; Imagine through the scenes,
    /// in weather of their own; the rest through the Library's mixes for focus, relaxing, sleep
    /// and meditating.
    enum Lens: String, CaseIterable {
        case outside = "Travel", imagine = "Imagine", focus = "Focus", relax = "Relax", sleep = "Sleep", meditate = "Meditate"

        var tag: Preset.Tag? {
            switch self {
            case .focus: .focus
            case .relax: .relax
            case .sleep: .sleep
            case .meditate: .meditate
            case .outside, .imagine: nil
            }
        }

        init(_ tag: Preset.Tag) {
            self = switch tag {
            case .focus: .focus
            case .relax: .relax
            case .sleep: .sleep
            case .meditate: .meditate
            }
        }
    }

    /// Nil when what's playing isn't on the wheel (one of yours): the wheel goes quiet, and
    /// swiping goes through Yours.
    private(set) var lens: Lens? = .outside

    /// The wheel following what's playing, when it was started some other way (the Library,
    /// Where to?, the menus): turned to its stop, or quiet, going through Yours.
    private func lensFollows(_ new: Lens?) {
        guard new != lens else { return }
        lens = new
        refreshUpcoming()
    }

    /// Turns the wheel to where that stop was left (Places, to the last place you were), or its
    /// first. Turning it, like swiping, only changes what's there: paused stays paused.
    func choose(_ new: Lens) {
        guard new != lens else { return }
        lens = new
        switch new {
        case .outside:
            if let p = pinnedPlace { select(p, play: false) } else { goHome() }
        case .imagine:
            go(to: atmosphere ?? Atmosphere.curated[0], play: false)
        default:
            let mixes = ring(new)
            let last = defaults.string(forKey: "lens.\(new.rawValue)")
            if let p = mixes.first(where: { $0.id == last }) ?? mixes.first { load(p, play: false) }
        }
        refreshUpcoming()
    }

    /// A lens's mixes, in order, going round.
    private func ring(_ lens: Lens) -> [Preset] {
        guard let tag = lens.tag else { return [] }
        return Preset.all.filter { $0.tag == tag }
    }

    /// The real places, going west from where you are, so swiping feels like turning a globe.
    private var placesWestward: [Place] {
        let home = homeCoordinate?.longitude ?? 0
        func west(_ p: Place) -> Double { (home - p.longitude).truncatingRemainder(dividingBy: 360) + (home < p.longitude ? 360 : 0) }
        return allPlaces.filter { !isNearHome($0) }.sorted { west($0) < west($1) }
    }

    /// Swiping travels round what the wheel is on, the next ones worked out ahead of time so the
    /// carousel can show them peeking in before you arrive.
    private(set) var upcoming: Destination?
    private(set) var upcomingBack: Destination?

    var next: Destination? { upcoming }
    var previous: Destination? { upcomingBack }

    private func refreshUpcoming() {
        func around(_ all: [Destination]) {
            guard all.count > 1 else { upcoming = nil; upcomingBack = nil; return }
            let i = all.firstIndex(of: here) ?? -1
            upcoming = all[(i + 1) % all.count]
            upcomingBack = all[(i - 1 + all.count) % all.count]
        }
        switch lens {
        case .outside?:
            around([.home] + placesWestward.map { .place($0) })
        case .imagine?:
            // The scenes, and the one you're in if it isn't one of them (imagined, or another sky).
            let scenes = Atmosphere.curated
            around(scenes.map { .atmosphere($0) } + (atmosphere.map { scenes.contains($0) ? [] : [.atmosphere($0)] } ?? []))
        case let lens?:
            around(ring(lens).map { .preset($0) })
        case nil:
            around(yoursItems.map { item in
                switch item {
                case .saved(let m): .preset(m.preset)
                case .kept(.scene(let a)): .atmosphere(a)
                case .kept(.mix(let p)): .preset(p)
                case .kept(.place(let p)): .place(p)
                }
            })
        }
    }

    /// A slide for the carousel to make, asked for from outside it (the keyboard, the menus,
    /// the menu bar, the media keys), so traveling looks the same as swiping.
    struct TravelRequest: Equatable {
        let id = UUID()
        let forward: Bool
    }
    private(set) var travelRequest: TravelRequest?
    /// Whether a carousel is on screen to take travel requests.
    @ObservationIgnored var carouselShowing = false

    /// Travels forward or back, sliding the carousel there if it's on screen.
    func requestTravel(forward: Bool) {
        guard forward ? next != nil : previous != nil else { return }
        if carouselShowing { travelRequest = TravelRequest(forward: forward) } else { travel(forward: forward) }
    }

    /// Swipe left (forward) to the next, or right (back). Paused stays paused.
    func travel(forward: Bool) {
        guard let dest = forward ? next : previous else { return }
        shuffleCount += 1
        switch dest {
        case .home: goHome()
        case .place(let p): select(p, play: false)
        case .atmosphere(let a): go(to: a, play: false)
        case .preset(let p): load(p, play: false)
        }
        refreshUpcoming()
    }

    /// How a destination would look, for the carousel's neighbouring pages.
    struct Page {
        var title: String
        var line: String
        var orbs: [Orb]
        /// The title over more than one line (an atmosphere's name).
        var lines: [String]? = nil
    }

    func page(for dest: Destination) -> Page {
        switch dest {
        case .home:
            guard let h = home else { return Page(title: "Home", line: "", orbs: []) }
            let o = Preset.layout(Self.applying(tweaks["home"], to: WeatherMix.orbs(for: h, place: homePlace)))
            return Page(title: h.mixName, line: "\(h.sceneDescription.capitalizedFirst) outside",
                        orbs: o)
        case .place(let p):
            let o: [Orb]
            let line: String
            if let c = placeConditions[p.name] {
                o = Preset.layout(Self.applying(tweaks[p.name], to: WeatherMix.orbs(for: c, place: p)))
                line = "\(c.sceneDescription.capitalizedFirst) in \(p.name)"
            } else {
                o = Preset.layout(p.signature.compactMap { k, v in k.playable.map { ($0, v) } })
                line = p.country
            }
            return Page(title: p.title, line: line, orbs: o)
        case .preset(let p):
            return Page(title: p.name, line: p.description, orbs: p.orbs)
        case .atmosphere(let a):
            let c = a.imagined()
            return Page(title: a.title(in: c), line: a.setting.info.line,
                        orbs: Preset.layout(Self.applying(tweaks[a.tweakKey], to: a.mix(in: c))), lines: a.lines(in: c))
        }
    }

    private func applyWeather(to mode: Mode, animated: Bool) {
        guard following[mode] == true else { return }
        let target: [(SoundKind, Double)]
        let name: String
        switch mode {
        case .mix: return
        case .match:
            guard let home else { return }
            target = Self.applying(tweaks["home"], to: WeatherMix.orbs(for: home, place: homePlace))
            name = home.mixName
        case .escape:
            guard let escape else { return }
            target = Self.applying(tweaks[escape.place.name], to: WeatherMix.orbs(for: escape.conditions, place: escape.place))
            name = escape.place.title
        case .atmosphere:
            guard let a = atmosphere, let c = atmosphereConditions else { return }
            target = Self.applying(tweaks[a.tweakKey], to: a.mix(in: c))
            name = a.title(in: c)
        }
        setTitle(name, for: mode)
        let orbs = Preset.layout(target)
        if animated && mode == self.mode {
            glide(to: orbs, duration: traveling ? 1.5 : 6)
            traveling = false
        } else {
            fields[mode] = orbs
            apply()
        }
    }

    /// Moves the current field to `target` with an equal-power crossfade: leaving sounds fade out
    /// as arriving ones fade in, so loudness stays even. Each light keeps its direction and only
    /// moves in or out, so position and volume change together.
    private func glide(to target: [Orb], duration: Double = 6) {
        transition?.cancel()
        let start = orbs
        struct Path { var orb: Orb; let angle: Double; let from: Double; let to: Double; let curve: Int }  // curve: 0 out, 1 in, 2 shared
        func angle(_ o: Orb) -> Double { atan2(o.y - 0.5, o.x - 0.5) }
        var paths: [Path] = []
        for t in target {
            if let s = start.first(where: { $0.kind == t.kind }) {
                paths.append(Path(orb: Orb(id: s.id, kind: t.kind, x: s.x, y: s.y), angle: angle(t),
                                  from: s.volume, to: t.volume, curve: 2))
            } else {
                paths.append(Path(orb: t, angle: angle(t), from: 0, to: t.volume, curve: 1))
            }
        }
        for s in start where !target.contains(where: { $0.kind == s.kind }) {
            paths.append(Path(orb: s, angle: angle(s), from: s.volume, to: 0, curve: 0))
        }

        let steps = max(1, Int(duration * 30))
        visualTarget = duration < 6 ? target : nil
        transition = Task { @MainActor [weak self] in
            defer { if !Task.isCancelled { self?.visualTarget = nil } }
            for step in 1...steps {
                guard let self, !Task.isCancelled else { return }
                let t = Double(step) / Double(steps)
                let eased = t * t * (3 - 2 * t)
                self.fields[self.mode] = paths.compactMap { p in
                    let v: Double
                    switch p.curve {
                    case 0: v = p.from * cos(t * .pi / 2)
                    case 1: v = p.to * sin(t * .pi / 2)
                    default: v = p.from + (p.to - p.from) * eased
                    }
                    if step == steps && p.curve == 0 { return nil }
                    var o = p.orb
                    let r = (1 - v) * 0.5
                    o.x = 0.5 + cos(p.angle) * r
                    o.y = 0.5 + sin(p.angle) * r
                    return o
                }
                // Each step only moves the sound; it's saved once, as the glide ends, so a swipe
                // that lands as the glide begins isn't kept waiting on the disk 30 times a second.
                if step == steps { self.apply() } else { self.sendLevels() }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    /// Sends the current field's volumes to the engine and saves.
    private func apply() {
        sendLevels()
        let encodable = Dictionary(uniqueKeysWithValues: fields.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) { defaults.set(data, forKey: "fields") }
        publishToWidgets()
    }

    /// Sends the current field's volumes to the engine.
    private func sendLevels() {
        var levels = Dictionary(uniqueKeysWithValues: SoundKind.allCases.map { ($0, 0.0) })
        for orb in orbs { levels[orb.kind] = max(levels[orb.kind]!, orb.volume) }
        // Each sound at its natural presence, and many layers at once kept under a ceiling.
        for (kind, gain) in Mix.gains(levels) { engine.setLevel(Float(gain), for: kind) }
    }

    // MARK: Playback

    func togglePlayback() {
        isPlaying ? stop() : play()
    }

    func play() {
        do {
            try engine.play()
            #if os(macOS)
            if !hasPlayed {
                hasPlayed = true
                setUpRemoteCommands()
            }
            #endif
            isPlaying = true
            scheduleTimer()
            updateNowPlaying()
        } catch {
            errorMessage = "Couldn't start audio: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine.stop()
        isPlaying = false
        timerWork?.cancel()
        updateNowPlaying()
        #if os(iOS)
        endActivitySoon()
        #endif
    }

    func setTimer(_ t: Timer) {
        timer = t
        if isPlaying { scheduleTimer() }
    }

    func cycleTimer() {
        let all = Timer.allCases
        timer = all[(all.firstIndex(of: timer)! + 1) % all.count]
        if isPlaying { scheduleTimer() }
    }

    private func scheduleTimer() {
        timerWork?.cancel()
        guard let seconds = timer.seconds else { return }
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        timerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
