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
    private(set) var home: Conditions?
    private(set) var escape: (place: Place, conditions: Conditions)?
    /// Live conditions at every place, keyed by name, for the globe and list.
    private(set) var placeConditions: [String: Conditions] = [:]
    /// A place the user chose. When nil, Escape picks the place least like home.
    private(set) var pinnedPlace: Place?
    /// Bumps on every random jump, so views can animate and play a haptic.
    private(set) var shuffleCount = 0
    /// Whether each mode's field is following the weather, or the user has taken over.
    private(set) var following: [Mode: Bool]

    @ObservationIgnored private let engine = NoiseEngine()
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
        pinnedPlace = defaults.string(forKey: "pinnedPlace").flatMap(Place.named)
        apply()
        setUpSystemAudio()
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

    private func updateNowPlaying() {
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
                    : "Tap Match outside to follow the weather"
                return WeatherSummary(place: home.place, temp: home.temperature, line: line, head: head)
            }
        case .escape:
            guard let escape else {
                return WeatherSummary(place: "", temp: "", line: "Finding somewhere else…", head: "Escaping outside")
            }
            let c = escape.conditions
            let line: String
            if following[.escape] != true {
                line = "Tap Escape outside to follow \(escape.place.name)"
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
    var byVolume: [Orb] { orbs.sorted { $0.volume > $1.volume } }

    /// "Brown 70  ·  Rain 45  ·  Wind 25"
    var layersLine: String {
        byVolume.map { "\($0.kind.short) \(Int(($0.volume * 100).rounded()))" }.joined(separator: "  ·  ")
    }

    var unusedSounds: [SoundKind] {
        let used = Set(orbs.map(\.kind))
        return SoundKind.allCases.filter { !used.contains($0) }
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
            home = try await weatherService.conditions(at: coordinate, place: place)
            weatherState = .ready
        } catch {
            weatherState = location.isDenied ? .locationOff : .failed
        }

        if let options = try? await weatherService.places() {
            placeConditions = Dictionary(uniqueKeysWithValues: zip(Place.all.map(\.name), options))
            chooseEscape()
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
        let options = Place.all.compactMap { p in placeConditions[p.name].map { (p, $0) } }
        guard !options.isEmpty else { return }
        let i = WeatherMix.bestEscape(from: home, options: options.map(\.1))
        escape = options[i]
    }

    /// Goes to a place: pins it, switches to Escape, and glides the field to its sound.
    func select(_ place: Place) {
        pinnedPlace = place
        defaults.set(place.name, forKey: "pinnedPlace")
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

    /// Jumps to a random place other than the current one.
    func shuffle() {
        let others = Place.all.filter { $0 != escape?.place && placeConditions[$0.name] != nil }
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
            glide(to: orbs)
        } else {
            fields[mode] = orbs
            apply()
        }
    }

    /// Moves the current field to `target` over a few seconds so the sound drifts rather than jumps.
    /// New sounds rise in from the rim; sounds that leave sink out to it.
    private func glide(to target: [Orb]) {
        transition?.cancel()
        let start = orbs
        func rim(_ o: Orb) -> (Double, Double) {
            let dx = o.x - 0.5, dy = o.y - 0.5
            let d = max(hypot(dx, dy), 0.0001)
            return (0.5 + dx / d * 0.5, 0.5 + dy / d * 0.5)
        }
        // (kind, from, to, keep)
        var paths: [(Orb, (Double, Double), (Double, Double), Bool)] = []
        for t in target {
            if let s = start.first(where: { $0.kind == t.kind }) {
                paths.append((Orb(id: s.id, kind: t.kind, x: s.x, y: s.y), (s.x, s.y), (t.x, t.y), true))
            } else {
                paths.append((t, rim(t), (t.x, t.y), true))
            }
        }
        for s in start where !target.contains(where: { $0.kind == s.kind }) {
            paths.append((s, (s.x, s.y), rim(s), false))
        }

        let steps = 120   // 6 s at 20 Hz
        transition = Task { @MainActor [weak self] in
            for step in 1...steps {
                guard let self, !Task.isCancelled else { return }
                let t = Double(step) / Double(steps)
                let eased = t * t * (3 - 2 * t)
                self.fields[self.mode] = paths.compactMap { orb, from, to, keep in
                    if step == steps && !keep { return nil }
                    var o = orb
                    o.x = from.0 + (to.0 - from.0) * eased
                    o.y = from.1 + (to.1 - from.1) * eased
                    return o
                }
                self.apply()
                try? await Task.sleep(for: .milliseconds(50))
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
