import CoreLocation
#if os(iOS)
import ActivityKit
import WidgetKit
#endif
import AVFoundation
import MediaPlayer
import SwiftUI
import Observation

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
    /// Live weather as fetched. Everything else reads the computed versions below, which apply
    /// any weather or time-of-day override.
    private var liveHome: Conditions?
    private var liveEscape: (place: Place, conditions: Conditions)?
    private var livePlaceConditions: [String: Conditions] = [:]

    var home: Conditions? { liveHome.map(overridden) }
    var escape: (place: Place, conditions: Conditions)? { liveEscape.map { ($0.place, overridden($0.conditions)) } }
    var placeConditions: [String: Conditions] { livePlaceConditions.mapValues(overridden) }

    // MARK: Overrides

    enum SkyOverride: String, CaseIterable {
        case live = "Live", clear = "Clear", drizzle = "Drizzle", rain = "Rain", downpour = "Downpour"
        case storm = "Storm", snow = "Snow", fog = "Fog", wind = "Windy"
    }
    enum TimeOverride: String, CaseIterable { case live = "Live", day = "Day", night = "Night" }

    private(set) var skyOverride: SkyOverride = .live
    private(set) var timeOverride: TimeOverride = .live
    var isImagining: Bool { skyOverride != .live || timeOverride != .live }

    func setSky(_ s: SkyOverride) {
        skyOverride = s
        defaults.set(s.rawValue, forKey: "skyOverride")
        reapplyAfterOverride()
    }

    func setTime(_ t: TimeOverride) {
        timeOverride = t
        defaults.set(t.rawValue, forKey: "timeOverride")
        reapplyAfterOverride()
    }

    /// Swipe down: the next weather in the list, wrapping back to Live.
    func cycleSky() {
        let all = SkyOverride.allCases
        setSky(all[(all.firstIndex(of: skyOverride)! + 1) % all.count])
    }

    /// Clears both overrides at once.
    func clearOverrides() {
        skyOverride = .live
        timeOverride = .live
        defaults.set(SkyOverride.live.rawValue, forKey: "skyOverride")
        defaults.set(TimeOverride.live.rawValue, forKey: "timeOverride")
        reapplyAfterOverride()
    }

    private func reapplyAfterOverride() {
        // An override is about a place's weather, so it takes you out of a Library mix.
        if activePreset != nil { setActivePreset(nil) }
        setFollowing(true, for: mode)
        traveling = true
        applyWeather(to: mode, animated: true)
        updateNowPlaying()
    }

    /// Live conditions with the chosen sky and time swapped in.
    private func overridden(_ c: Conditions) -> Conditions {
        var c = c
        switch timeOverride {
        case .live: break
        case .day: c.isDay = true; c.forcedPhase = .day
        case .night: c.isDay = false; c.forcedPhase = .night
        }
        switch skyOverride {
        case .live: break
        case .clear: c.code = 0; c.precipitationMM = 0; c.windKMH = min(c.windKMH, 10)
        case .drizzle: c.code = 53; c.precipitationMM = 0.2
        case .rain: c.code = 63; c.precipitationMM = 1.5
        case .downpour: c.code = 65; c.precipitationMM = 8
        case .storm: c.code = 95; c.precipitationMM = max(c.precipitationMM, 4); c.windKMH = max(c.windKMH, 35); c.pressureHPA = min(c.pressureHPA, 998)
        case .snow: c.code = 73; c.precipitationMM = 0; c.temperatureC = min(c.temperatureC, -2)
        case .fog: c.code = 45; c.precipitationMM = 0; c.windKMH = min(c.windKMH, 6)
        case .wind: c.code = 3; c.precipitationMM = 0; c.windKMH = max(c.windKMH, 45)
        }
        return c
    }

    /// "Imagining a rainy night in Tokyo".
    func imaginingLine(at place: String) -> String {
        let sky: String? = {
            switch skyOverride {
            case .live: return nil
            case .clear: return timeOverride == .live ? "clear skies" : "clear"
            case .drizzle: return timeOverride == .live ? "drizzle" : "drizzly"
            case .rain: return timeOverride == .live ? "rain" : "rainy"
            case .downpour: return timeOverride == .live ? "a downpour" : "pouring"
            case .storm: return timeOverride == .live ? "a storm" : "stormy"
            case .snow: return timeOverride == .live ? "snow" : "snowy"
            case .fog: return timeOverride == .live ? "fog" : "foggy"
            case .wind: return timeOverride == .live ? "wind" : "windy"
            }
        }()
        let time: String? = timeOverride == .live ? nil : timeOverride.rawValue.lowercased()
        switch (sky, time) {
        case let (s?, t?): return "Imagining a \(s) \(t) in \(place)"
        case let (s?, nil): return "Imagining \(s) in \(place)"
        case let (nil, t?): return "Imagining \(t) in \(place)"
        default: return ""
        }
    }
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
            .escape: defaults.string(forKey: "title.escape") ?? "Warm Night",
            .atmosphere: defaults.string(forKey: "title.atmosphere") ?? "",
        ]
        following = [
            .match: defaults.object(forKey: "following.match") as? Bool ?? true,
            .escape: defaults.object(forKey: "following.escape") as? Bool ?? true,
            .atmosphere: defaults.object(forKey: "following.atmosphere") as? Bool ?? true,
        ]
        atmosphere = defaults.data(forKey: "atmosphere").flatMap { try? JSONDecoder().decode(Atmosphere.self, from: $0) }
        if let raw = defaults.string(forKey: "mode"), let saved = Mode(rawValue: raw) { mode = saved }
        customPlaces = (defaults.array(forKey: "customPlaces") as? [[String: Any]] ?? []).compactMap(Place.init(dictionary:)).map(Self.refreshed)
        pinnedPlace = defaults.string(forKey: "pinnedPlace").flatMap { name in allPlaces.first { $0.name == name } }
        skyOverride = defaults.string(forKey: "skyOverride").flatMap(SkyOverride.init(rawValue:)) ?? .live
        timeOverride = defaults.string(forKey: "timeOverride").flatMap(TimeOverride.init(rawValue:)) ?? .live
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
        lens = activePreset?.tag.map(Lens.init) ?? (mode == .atmosphere ? .scenes : .outside)
        refreshUpcoming()
        apply()
        if mode == .atmosphere { applyWeather(to: .atmosphere, animated: false) }
        setUpSystemAudio()
        startClock()
        PlayPauseIntent.handler = { [weak self] in self?.togglePlayback() }
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
            let line = title == preset.name ? preset.description : "Started from \(preset.name)"
            return WeatherSummary(place: "Library", temp: "", line: line, head: "Library mix")
        }
        switch mode {
        case .match:
            let head = following[.match] == true ? "Matching outside" : "Your mix"
            switch weatherState {
            case .loading where home == nil:
                return WeatherSummary(place: "", temp: "", line: "Checking the weather…", head: head)
            case .locationOff:
                return WeatherSummary(place: "Location off", temp: "",
                                      line: "Allow location in Settings to match outside", head: "Your mix")
            case .failed where home == nil:
                return WeatherSummary(place: "Offline", temp: "", line: "Couldn't reach the weather", head: head)
            default:
                guard let home else { return WeatherSummary(place: "", temp: "", line: "", head: head) }
                let line = following[.match] == true
                    ? (isImagining ? imaginingLine(at: home.place) : "\(home.sceneDescription.capitalizedFirst) outside") + (tweaks["home"] != nil ? " · tuned by you" : "")
                    : "Your own mix, made here"
                return WeatherSummary(place: home.place, temp: home.temperature, line: line, head: head)
            }
        case .escape:
            guard let escape else {
                if let pinned = pinnedPlace {
                    return WeatherSummary(place: pinned.title, temp: "", line: "Checking the weather in \(pinned.name)…",
                                          head: "Escaping to \(pinned.name)")
                }
                return WeatherSummary(place: "", temp: "", line: "Finding somewhere else…", head: "Escaping outside")
            }
            let c = escape.conditions
            let line: String
            if following[.escape] != true {
                line = "Your own mix, made in \(escape.place.name)"
            } else if pinnedPlace != nil {
                line = (isImagining ? imaginingLine(at: escape.place.name) : "\(c.sceneDescription.capitalizedFirst) in \(escape.place.name)")
                    + (tweaks[escape.place.name] != nil ? " · tuned by you" : "")
            } else {
                line = Self.escapeLine(c)
            }
            return WeatherSummary(place: escape.place.title, temp: c.temperature, line: line,
                                  head: "Escaping to \(escape.place.name)")
        case .atmosphere:
            guard let a = atmosphere else { return WeatherSummary(place: "", temp: "", line: "", head: "Atmosphere") }
            let line = following[.atmosphere] != true ? "Your own mix, made from \(a.setting.info.name.lowercased())"
                : a.setting.info.line + (tweaks[a.tweakKey] != nil ? " · tuned by you" : "")
            return WeatherSummary(place: a.setting.info.name, temp: "", line: line, head: "Atmosphere")
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
        lensFollows(.scenes)
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

    /// Drops a new sound in near the bottom of the field, quiet, ready to drag in.
    func add(_ kind: SoundKind) {
        fields[mode, default: []].append(Orb(kind: kind, x: 0.5 + (Double.random(in: -0.15...0.15)), y: 0.86))
        markCustom()
        apply()
    }

    /// A Library mix that's playing. It stands on its own, apart from any place's weather.
    private(set) var activePreset: Preset?

    // MARK: Saved mixes

    private(set) var savedMixes: [SavedMix] = []

    /// A name to start from when saving, e.g. "Waterford, light rain".
    var suggestedSaveName: String {
        if let p = activePreset, title == p.name { return "\(p.name) (mine)" }
        if title == "Your mix" { return "My mix \(savedMixes.count + 1)" }
        if mode == .escape, let e = escape { return "\(e.place.title), \(e.conditions.mixName.lowercased())" }
        if mode == .atmosphere, atmosphere != nil { return title }
        if let h = home { return "\(h.place), \(h.mixName.lowercased())" }
        return title
    }

    private var saveOrigin: String {
        let date = Date().formatted(.dateTime.month(.abbreviated).day())
        if let p = activePreset { return title == p.name ? "Copy of \(p.name), \(date)" : "Started from \(p.name), \(date)" }
        if title == "Your mix" { return "Made in Layers, \(date)" }
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
        setTitle(mix.name, for: mode)
    }

    func rename(_ mix: SavedMix, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = savedMixes.firstIndex(of: mix) else { return }
        savedMixes[i].name = trimmed
        persistSaved()
        if activePreset?.savedID == mix.id {
            setActivePreset(savedMixes[i].preset)
            setTitle(trimmed, for: mode)
        }
    }

    func delete(_ mix: SavedMix) {
        savedMixes.removeAll { $0.id == mix.id }
        persistSaved()
        if isFavorite(Self.favoriteKey(mix.preset)) { toggleFavorite(Self.favoriteKey(mix.preset)) }
        if activePreset?.savedID == mix.id { setActivePreset(nil) }
    }

    // MARK: Favorites

    /// What you've marked as a favorite, newest first: Library mixes (`mix:` and the mix's ID) and
    /// scenes (`scene:` and the atmosphere's ID). Kept on this device.
    private(set) var favorites: [String] = UserDefaults.standard.stringArray(forKey: "favorites") ?? []

    func isFavorite(_ key: String) -> Bool { favorites.contains(key) }

    func toggleFavorite(_ key: String) {
        if let i = favorites.firstIndex(of: key) {
            favorites.remove(at: i)
            announce("Removed from Favorites")
        } else {
            favorites.insert(key, at: 0)
            announce("Added to Favorites in your Library")
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

    /// What's playing, as something to favorite: a Library mix or a scene (not your own weather).
    var favoriteKey: String? {
        if let p = activePreset { return Self.favoriteKey(p) }
        if mode == .atmosphere, let a = atmosphere { return Self.favoriteKey(a) }
        return nil
    }

    enum Favorite: Identifiable {
        case scene(Atmosphere), mix(Preset)
        var id: String {
            switch self {
            case .scene(let a): Mixer.favoriteKey(a)
            case .mix(let p): Mixer.favoriteKey(p)
            }
        }
    }

    /// Your favorites, newest first, as things to play.
    var favoriteItems: [Favorite] {
        let mixes = savedMixes.map(\.preset) + Preset.all
        return favorites.compactMap { key in
            if key.hasPrefix("scene:"), let a = Atmosphere(id: String(key.dropFirst(6))) { return .scene(a) }
            if key.hasPrefix("mix:"), let p = mixes.first(where: { Self.favoriteKey($0) == key }) { return .mix(p) }
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

    func moveSavedMixes(from source: IndexSet, to destination: Int) {
        savedMixes.move(fromOffsets: source, toOffset: destination)
        persistSaved()
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

    /// A symbol for the weather outside, beside it.
    var outsideSymbol: String { liveHome?.symbol ?? "location" }

    /// Where "Back to …" returns from a Library mix: the place you were in, or home.
    var presetReturnName: String {
        if mode == .escape, let p = escape?.place { return p.name }
        if mode == .atmosphere, let a = atmosphere { return a.setting.info.name.lowercased() }
        return homeName
    }

    /// Leaves a Library mix and follows the weather where you were.
    func leavePreset() {
        setActivePreset(nil)
        traveling = true
        followWeatherAgain()
        lensFollows(mode == .atmosphere ? .scenes : .outside)
    }

    func load(_ preset: Preset) {
        transition?.cancel()
        setActivePreset(preset)
        setFollowing(false, for: mode)
        fields[mode] = preset.orbs
        titles[mode] = preset.name
        defaults.set(preset.name, forKey: "title.\(mode.rawValue)")
        apply()
        if !isPlaying { play() }
        arrived()
        if let tag = preset.tag {
            defaults.set(preset.id, forKey: "lens.\(Lens(tag).rawValue)")
            lensFollows(Lens(tag))
        }
    }

    private func update(_ id: Orb.ID, _ change: (inout Orb) -> Void) {
        guard let i = fields[mode]?.firstIndex(where: { $0.id == id }) else { return }
        change(&fields[mode]![i])
        markCustom()
        apply()
    }

    private func markCustom() {
        // At a place (or home) that's following the weather, an edit becomes a lasting tweak to
        // that place instead of breaking away from it.
        if activePreset == nil, following[mode] == true, let key = tweakKey {
            recordTweaks(for: key)
            return
        }
        setFollowing(false, for: mode)
        guard titles[mode] != "Your mix" else { return }
        setTitle("Your mix", for: mode)
    }

    // MARK: Per-place tweaks

    /// Volume changes you've made to a place, by sound: added on top of what the weather gives.
    private(set) var tweaks: [String: [String: Double]] = [:]

    /// The place the field belongs to right now ("home" for home), if it's following the weather.
    private var tweakKey: String? {
        guard activePreset == nil else { return nil }
        if mode == .escape { return escape?.place.name }
        if mode == .atmosphere { return atmosphere?.tweakKey }
        return "home"
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
        case .match: "home"
        }
    }

    /// What the weather alone gives this mode, before tweaks.
    private func baseMix(for mode: Mode) -> [(SoundKind, Double)]? {
        switch mode {
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

    /// Puts the current place back to how it sounds by default, following the weather.
    func resetCurrentPlace() {
        if let key = tweakKey {
            tweaks[key] = nil
            persistTweaks()
        }
        traveling = true
        applyWeather(to: mode, animated: true)
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
    func select(_ place: Place) {
        setActivePreset(nil)
        // Choosing the place you're already in is just going home.
        if isNearHome(place) {
            pinnedPlace = nil
            defaults.removeObject(forKey: "pinnedPlace")
            goHome()
            if !isPlaying { play() }
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
        if !isPlaying { play() }
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

    /// What the wheel at the top is turned to: what swiping goes through. Outside goes round home
    /// and the real places, Scenes through the atmospheres, and the rest through the Library's
    /// mixes for sleep, focus, relaxing and meditating.
    enum Lens: String, CaseIterable {
        case outside = "Outside", scenes = "Scenes", focus = "Focus", relax = "Relax", sleep = "Sleep", meditate = "Meditate"

        var tag: Preset.Tag? {
            switch self {
            case .focus: .focus
            case .relax: .relax
            case .sleep: .sleep
            case .meditate: .meditate
            case .outside, .scenes: nil
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

    private(set) var lens: Lens = .outside

    /// The lens that fits what's playing, when it was started some other way (the Library,
    /// Teleport, the weather button). A mix of your own leaves the wheel where it is.
    private func lensFollows(_ new: Lens?) {
        guard let new, new != lens else { return }
        lens = new
        backStack = []
        refreshUpcoming()
    }

    /// Turns the wheel: plays where that lens was left, or its first.
    func choose(_ new: Lens) {
        guard new != lens else { return }
        lens = new
        backStack = []
        switch new {
        case .outside:
            goHome()
            if !isPlaying { play() }
        case .scenes:
            go(to: atmosphere ?? draw(excluding: []))
        default:
            let mixes = ring(new)
            let last = defaults.string(forKey: "lens.\(new.rawValue)")
            if let p = mixes.first(where: { $0.id == last }) ?? mixes.first { load(p) }
        }
        refreshUpcoming()
    }

    /// A lens's mixes, in order, going round.
    private func ring(_ lens: Lens) -> [Preset] {
        guard let tag = lens.tag else { return [] }
        return Preset.all.filter { $0.tag == tag }
    }

    /// Swiping travels through the lens, the next ones picked ahead of time so the carousel can
    /// show them peeking in before you arrive. In Scenes, back goes through where you've been.
    private(set) var upcoming: Destination?
    private(set) var upcomingBack: Destination?
    private(set) var backStack: [Destination] = []
    /// The hand-picked atmospheres, shuffled, so you hear them all before any comes round again.
    @ObservationIgnored private var deck: [Atmosphere] = []

    var next: Destination? { upcoming }
    var previous: Destination? { lens == .scenes ? backStack.last ?? upcomingBack : upcomingBack }

    private func draw(excluding: [Atmosphere?]) -> Atmosphere {
        if deck.isEmpty { deck = Atmosphere.curated.shuffled() }
        let i = deck.firstIndex { a in !excluding.contains(a) } ?? 0
        return deck.remove(at: i)
    }

    private func refreshUpcoming() {
        func around(_ all: [Destination]) {
            guard all.count > 1 else { upcoming = nil; upcomingBack = nil; return }
            let i = all.firstIndex(of: here) ?? -1
            upcoming = all[(i + 1) % all.count]
            upcomingBack = all[(i - 1 + all.count) % all.count]
        }
        switch lens {
        case .scenes:
            let ahead = draw(excluding: [atmosphere])
            upcoming = .atmosphere(ahead)
            upcomingBack = .atmosphere(draw(excluding: [atmosphere, ahead]))
        case .outside:
            around([.home] + allPlaces.filter { !isNearHome($0) }.map { .place($0) })
        default:
            around(ring(lens).map { .preset($0) })
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

    /// Swipe left (forward) to the next in the lens, or right (back).
    func travel(forward: Bool) {
        guard let dest = forward ? next : previous else { return }
        if lens == .scenes {
            if forward {
                backStack.append(here)
            } else if !backStack.isEmpty {
                backStack.removeLast()
            }
        }
        shuffleCount += 1
        switch dest {
        case .home: goHome(); if !isPlaying { play() }
        case .place(let p): select(p)
        case .atmosphere(let a): go(to: a)
        case .preset(let p): load(p)
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
            return Page(title: h.mixName, line: isImagining ? imaginingLine(at: h.place) : "\(h.sceneDescription.capitalizedFirst) outside",
                        orbs: o)
        case .place(let p):
            let o: [Orb]
            let line: String
            if let c = placeConditions[p.name] {
                o = Preset.layout(Self.applying(tweaks[p.name], to: WeatherMix.orbs(for: c, place: p)))
                line = isImagining ? imaginingLine(at: p.name) : "\(c.sceneDescription.capitalizedFirst) in \(p.name)"
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
