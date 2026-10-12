import CoreLocation
import ActivityKit
import AVFoundation
import WidgetKit
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
    private(set) var home: Conditions?
    private(set) var escape: (place: Place, conditions: Conditions)?
    /// Live conditions at every place, keyed by name, for the globe and list.
    private(set) var placeConditions: [String: Conditions] = [:]
    /// A place the user chose. When nil, Escape picks the place least like home.
    private(set) var pinnedPlace: Place?
    /// Places found through search, newest first.
    private(set) var customPlaces: [Place] = []
    var allPlaces: [Place] { customPlaces + Place.all }

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

    init() {
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
        ]
        following = [
            .match: defaults.object(forKey: "following.match") as? Bool ?? true,
            .escape: defaults.object(forKey: "following.escape") as? Bool ?? true,
        ]
        if let raw = defaults.string(forKey: "mode"), let saved = Mode(rawValue: raw) { mode = saved }
        customPlaces = (defaults.array(forKey: "customPlaces") as? [[String: Any]] ?? []).compactMap(Place.init(dictionary:))
        pinnedPlace = defaults.string(forKey: "pinnedPlace").flatMap { name in allPlaces.first { $0.name == name } }
        apply()
        setUpSystemAudio()
        PlayPauseIntent.handler = { [weak self] in self?.togglePlayback() }
    }

    // MARK: Lock screen, interruptions, route changes

    @ObservationIgnored private var resumeAfterInterruption = false

    private func setUpSystemAudio() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        commands.pauseCommand.addTarget { [weak self] _ in self?.stop(); return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayback(); return .success }

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
    }

    // MARK: Widget and Live Activity

    @ObservationIgnored private var activity: Activity<SoundscapeActivity>?
    @ObservationIgnored private var lastSnapshot: NowPlayingSnapshot?
    @ObservationIgnored private var lastSnapshotSave = Date.distantPast

    /// Shares what's playing with the widget, and keeps the Live Activity in step.
    private func publishToWidgets() {
        // Away, the title is the place's name, so show its weather as the title instead.
        let conditions = mode == .escape ? escape?.conditions : home
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

    private func updateNowPlaying() {
        publishToWidgets()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Atmospherics",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let image = UIImage(named: "Artwork") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    // MARK: Reading

    var orbs: [Orb] { fields[mode] ?? [] }
    var title: String { titles[mode] ?? "" }
    var weather: WeatherSummary {
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
                    ? "Following \(home.subject) outside"
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
                line = "\(c.mixName) in \(escape.place.name) right now"
            } else {
                line = Self.escapeLine(c)
            }
            return WeatherSummary(place: escape.place.title, temp: c.temperature, line: line,
                                  head: "Escaping to \(escape.place.name)")
        }
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

    /// "Brown 70  ·  Rain 45  ·  Wind 25"
    var layersLine: String {
        byVolume.filter { $0.volume >= 0.05 }.map { "\($0.kind.short) \(Int(($0.volume * 100).rounded()))" }.joined(separator: "  ·  ")
    }

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

    /// Nudges an orb toward (positive) or away from (negative) the center. Used by VoiceOver.
    func adjustVolume(_ id: Orb.ID, by delta: Double) {
        guard let orb = orbs.first(where: { $0.id == id }) else { return }
        let target = max(0, min(1, orb.volume + delta))
        let dx = orb.x - 0.5, dy = orb.y - 0.5
        let d = max(hypot(dx, dy), 0.0001)
        let r = (1 - target) * 0.5
        let (ux, uy) = d < 0.001 ? (0.0, 1.0) : (dx / d, dy / d)
        update(id) { $0.x = 0.5 + ux * r; $0.y = 0.5 + uy * r }
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

    func load(_ preset: Preset) {
        transition?.cancel()
        setFollowing(false, for: mode)
        fields[mode] = preset.orbs
        titles[mode] = preset.name
        defaults.set(preset.name, forKey: "title.\(mode.rawValue)")
        apply()
        if !isPlaying { play() }
    }

    private func update(_ id: Orb.ID, _ change: (inout Orb) -> Void) {
        guard let i = fields[mode]?.firstIndex(where: { $0.id == id }) else { return }
        change(&fields[mode]![i])
        markCustom()
        apply()
    }

    private func markCustom() {
        setFollowing(false, for: mode)
        guard titles[mode] != "Your mix" else { return }
        setTitle("Your mix", for: mode)
    }

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

        do {
            let (coordinate, place) = try await location.current()
            homeCoordinate = coordinate
            home = try await weatherService.conditions(at: coordinate, place: place)
            weatherState = .ready
        } catch {
            weatherState = location.isDenied ? .locationOff : .failed
        }

        let places = allPlaces
        if let options = try? await weatherService.conditions(for: places) {
            placeConditions = Dictionary(zip(places.map(\.name), options), uniquingKeysWith: { a, _ in a })
            chooseEscape()
            if upcoming == nil { refreshUpcoming() }
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
    }

    /// Uses the pinned place if there is one, otherwise the place least like home.
    private func chooseEscape() {
        if let pinned = pinnedPlace, let c = placeConditions[pinned.name] {
            escape = (pinned, c)
            return
        }
        let options = Place.all.compactMap { p in placeConditions[p.name].map { (p, $0) } }   // curated places only
        guard !options.isEmpty else { return }
        let i = WeatherMix.bestEscape(from: home, options: options.map(\.1))
        escape = options[i]
    }

    /// Goes to a place: pins it, switches to Escape, and glides the field to its sound.
    func select(_ place: Place) {
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
    }

    /// Saves a searched place, fetches its weather, and goes there.
    func addAndSelect(_ place: Place) async {
        customPlaces.removeAll { $0.name == place.name }
        customPlaces.insert(place, at: 0)
        customPlaces = Array(customPlaces.prefix(8))
        defaults.set(customPlaces.map(\.dictionary), forKey: "customPlaces")
        if let c = try? await weatherService.conditions(for: [place]).first {
            placeConditions[place.name] = c
        }
        select(place)
    }

    func removeCustom(_ place: Place) {
        customPlaces.removeAll { $0.name == place.name }
        defaults.set(customPlaces.map(\.dictionary), forKey: "customPlaces")
        if pinnedPlace == place { unpinPlace() }
    }

    /// Comes back from a place to the local weather.
    func goHome() {
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
    }

    /// Hands an edited field back to the weather, without leaving the place.
    func followWeatherAgain() {
        setFollowing(true, for: mode)
        applyWeather(to: mode, animated: true)
    }

    /// Where home is on the map, to tell when a chosen place is really just home.
    @ObservationIgnored private var homeCoordinate: CLLocationCoordinate2D?

    private func isNearHome(_ place: Place) -> Bool {
        guard let h = homeCoordinate else { return false }
        let here = CLLocation(latitude: h.latitude, longitude: h.longitude)
        return here.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) < 40_000
    }

    /// Where "home" is, for the "Back to …" line.
    var homeName: String { home?.place ?? "home" }

    // MARK: Carousel

    enum Destination: Equatable {
        case home
        case place(Place)
    }

    /// Where the field is now.
    var here: Destination {
        if mode == .escape, let p = escape?.place { return .place(p) }
        return .home
    }

    /// Picked ahead of time so the carousel can show it peeking in before you arrive.
    private(set) var upcoming: Place?
    private(set) var upcomingBack: Place?
    private(set) var backStack: [Destination] = []

    var next: Destination? { (upcoming ?? pickRandom()).map { .place($0) } }
    var previous: Destination? { backStack.last ?? upcomingBack.map { .place($0) } }

    private func pickRandom(excluding: [Place] = []) -> Place? {
        let current: Place? = { if case .place(let p) = here { return p }; return nil }()
        return allPlaces.filter { p in
            p != current && !excluding.contains(p) && placeConditions[p.name] != nil && !isNearHome(p)
        }.randomElement()
    }

    private func refreshUpcoming() {
        upcoming = pickRandom()
        upcomingBack = pickRandom(excluding: upcoming.map { [$0] } ?? [])
    }

    /// Swipe left (forward) to a new place, or right (back) through where you've been.
    func travel(forward: Bool) {
        guard let dest = forward ? next : previous else { return }
        if forward {
            backStack.append(here)
        } else if !backStack.isEmpty {
            backStack.removeLast()
        }
        shuffleCount += 1
        switch dest {
        case .home: goHome()
        case .place(let p): select(p)
        }
        refreshUpcoming()
    }

    /// How a destination would look, for the carousel's neighbouring pages.
    struct Page {
        var title: String
        var line: String
        var layers: String
        var orbs: [Orb]
    }

    func page(for dest: Destination) -> Page {
        func layers(_ o: [Orb]) -> String {
            o.sorted { $0.volume > $1.volume }.filter { $0.volume >= 0.05 }
                .map { "\($0.kind.short) \(Int(($0.volume * 100).rounded()))" }.joined(separator: "  ·  ")
        }
        switch dest {
        case .home:
            guard let h = home else { return Page(title: "Home", line: "", layers: "", orbs: []) }
            let o = Preset.layout(WeatherMix.orbs(for: h))
            return Page(title: h.mixName, line: "Following \(h.subject) outside", layers: layers(o), orbs: o)
        case .place(let p):
            let o: [Orb]
            let line: String
            if let c = placeConditions[p.name] {
                o = Preset.layout(WeatherMix.orbs(for: c, place: p))
                line = "\(c.mixName) in \(p.name) right now"
            } else {
                o = Preset.layout(p.signature.compactMap { k, v in k.playable.map { ($0, v) } })
                line = p.country
            }
            return Page(title: p.title, line: line, layers: layers(o), orbs: o)
        }
    }

    /// Jumps to a random place other than the current one.
    func shuffle() {
        let others = allPlaces.filter { $0 != escape?.place && placeConditions[$0.name] != nil && !isNearHome($0) }
        guard let place = others.randomElement() ?? Place.all.randomElement() else { return }
        shuffleCount += 1
        select(place)
    }

    /// Lets Escape pick automatically again (the place least like home).
    func unpinPlace() {
        pinnedPlace = nil
        defaults.removeObject(forKey: "pinnedPlace")
        chooseEscape()
        applyWeather(to: .escape, animated: true)
    }

    private func applyWeather(to mode: Mode, animated: Bool) {
        guard following[mode] == true else { return }
        let target: [(SoundKind, Double)]
        let name: String
        switch mode {
        case .match:
            guard let home else { return }
            target = WeatherMix.orbs(for: home)
            name = home.mixName
        case .escape:
            guard let escape else { return }
            target = WeatherMix.orbs(for: escape.conditions, place: escape.place)
            name = escape.place.title
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
                self.apply()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    /// Sends the current field's volumes to the engine and saves.
    private func apply() {
        var levels = Dictionary(uniqueKeysWithValues: SoundKind.allCases.map { ($0, 0.0) })
        for orb in orbs { levels[orb.kind] = max(levels[orb.kind]!, orb.volume) }
        for (kind, level) in levels { engine.setLevel(Float(level), for: kind) }

        let encodable = Dictionary(uniqueKeysWithValues: fields.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) { defaults.set(data, forKey: "fields") }
        publishToWidgets()
    }

    // MARK: Playback

    func togglePlayback() {
        isPlaying ? stop() : play()
    }

    func play() {
        do {
            try engine.play()
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
        endActivitySoon()
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
