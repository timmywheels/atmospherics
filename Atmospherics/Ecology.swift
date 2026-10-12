import Foundation

// How a place actually sounds right now: which of its sounds are in season, awake at this hour,
// warm enough to be out, and how the weather changes them.

/// The broad climate of a place. It decides whether there are seasons, whether the trees lose
/// their leaves, and whether lakes freeze.
enum Climate: String {
    case tropical       // no real seasons; wet and dry months instead
    case arid           // desert and semi-desert
    case mediterranean  // dry summers, mild wet winters, mostly evergreen
    case subtropical    // hot humid summers, mild winters
    case temperate      // four mild seasons
    case continental    // four seasons, cold snowy winters
    case subpolar       // short cool summers, long dark winters

    static func of(latitude: Double) -> Climate {
        switch abs(latitude) {
        case ..<23.5: .tropical
        case ..<35: .subtropical
        case ..<58: .temperate
        default: .subpolar
        }
    }

    var hasSeasons: Bool { self != .tropical }
    var deciduous: Bool { [.subtropical, .temperate, .continental].contains(self) }
    var lakesFreeze: Bool { [.continental, .subpolar].contains(self) }
}

enum Season: String { case spring, summer, autumn, winter }

enum DayPhase: String { case dawn, day, dusk, night }

extension Conditions {
    /// The local calendar at the place, from its UTC offset.
    func localTime(at date: Date = Date()) -> (month: Int, weekday: Int, hour: Int, minute: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffset) ?? .gmt
        let c = calendar.dateComponents([.month, .weekday, .hour, .minute], from: date)
        return (c.month ?? 1, c.weekday ?? 1, c.hour ?? 12, c.minute ?? 0)
    }

    /// The month as the northern hemisphere would feel it, so seasonal rules are written once:
    /// south of the equator, October behaves like April.
    func seasonalMonth(at date: Date = Date()) -> Int {
        let m = localTime(at: date).month
        return latitude >= 0 ? m : (m + 5) % 12 + 1
    }

    func season(at date: Date = Date()) -> Season? {
        guard abs(latitude) >= 23.5 else { return nil }
        switch seasonalMonth(at: date) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    /// Dawn and dusk come from the real sunrise and sunset there.
    func phase(at date: Date = Date()) -> DayPhase {
        if let forcedPhase { return forcedPhase }
        guard let sunrise, let sunset, sunset - sunrise > 90 else { return isDay ? .day : .night }
        let t = localTime(at: date)
        let now = t.hour * 60 + t.minute
        if now >= sunrise - 50 && now < sunrise + 70 { return .dawn }
        if now >= sunset - 50 && now < sunset + 40 { return .dusk }
        if now >= sunrise + 70 && now < sunset - 50 { return .day }
        return .night
    }

    // MARK: Words

    private func phaseWord(_ date: Date) -> String {
        switch phase(at: date) {
        case .dawn: return "dawn"
        case .dusk: return "evening"
        case .night: return "night"
        case .day: return localTime(at: date).hour < 12 ? "morning" : "afternoon"
        }
    }

    /// "Autumn", or in the tropics "Warm" / "Cool".
    private func whenWord(_ date: Date) -> String {
        if let s = season(at: date) { return s.rawValue.capitalized }
        return temperatureC >= 22 ? "Warm" : "Cool"
    }

    /// A short name for the scene, e.g. "Autumn Night", "Summer Storm", "Warm Drizzle".
    var mixName: String { mixName(at: Date()) }

    func mixName(at date: Date) -> String {
        let whenWord = whenWord(date), phaseWord = phaseWord(date)
        if isThunder { return "\(whenWord) Storm" }
        if isSnow { return "Snowfall" }
        if isRaining {
            switch rainIntensity {
            case .light: return "\(whenWord) Drizzle"
            case .moderate: return "\(whenWord) Rain"
            case .heavy: return "\(whenWord) Downpour"
            }
        }
        if isFog { return "\(whenWord) Fog" }
        if windKMH > 30 { return "Windy \(phaseWord.capitalized)" }
        return "\(whenWord) \(phaseWord.capitalized)"
    }

    /// The scene in a phrase, e.g. "a clear autumn night", "drizzle on a spring morning".
    var sceneDescription: String { sceneDescription(at: Date()) }

    func sceneDescription(at date: Date) -> String {
        // "autumn night"; in the tropics, where there are no seasons, "warm night".
        let season = season(at: date)?.rawValue
        let warm = season == nil && temperatureC >= 22
        let when = [season ?? (warm ? "warm" : nil), phaseWord(date)].compactMap { $0 }.joined(separator: " ")
        func a(_ s: String) -> String { ("aeiou".contains(s.first ?? "x") ? "an " : "a ") + s }
        // "a clear autumn night", but "a warm, clear night".
        func described(_ adjective: String) -> String {
            warm ? "a warm, \(adjective) \(phaseWord(date))" : a("\(adjective) \(when)")
        }
        if isThunder { return "a storm on " + a(when) }
        if isSnow { return "snow on " + a(when) }
        if isRaining {
            switch rainIntensity {
            case .light: return "drizzle on " + a(when)
            case .moderate: return "rain on " + a(when)
            case .heavy: return "a downpour on " + a(when)
            }
        }
        if isFog { return "fog on " + a(when) }
        if windKMH > 30 { return described("windy") }
        if code >= 2 { return described("cloudy") }
        return described("clear")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Who's out right now

enum Ecology {
    /// How present one of a place's sounds is right now, about 0…1.2, before the weather.
    /// Birds sing in spring, not October; crickets need warm late-summer nights; loons leave in
    /// autumn; the city quiets at 3am; café terraces close; bells ring on the hour.
    static func activity(of kind: SoundKind, at place: Place?, in c: Conditions, now: Date) -> Double {
        let climate = place?.climate ?? Climate.of(latitude: c.latitude)
        let tropical = !climate.hasSeasons
        let t = c.localTime(at: now)
        let m = c.seasonalMonth(at: now)
        let phase = c.phase(at: now)
        let temp = c.temperatureC

        /// Wet season in the tropics brings out the frogs.
        let wet: Double = {
            guard let months = place?.wetMonths, !months.isEmpty else { return 1 }
            return months.contains(t.month) ? 1.25 : 0.6
        }()
        func by(_ dawn: Double, _ day: Double, _ dusk: Double, _ night: Double) -> Double {
            switch phase {
            case .dawn: dawn
            case .day: day
            case .dusk: dusk
            case .night: night
            }
        }
        func month(_ table: [Int: Double]) -> Double { table[m] ?? 0 }
        func ramp(_ x: Double, _ from: Double, _ to: Double) -> Double { min(1, max(0, (x - from) / (to - from))) }

        switch kind {
        // Birds: a full chorus at a spring dawn, a few calls in autumn, near silence in winter.
        case .birds:
            let p = by(1, 0.55, 0.3, 0)
            if tropical { return p }
            var s = month([1: 0.03, 2: 0.05, 3: 0.4, 4: 0.9, 5: 1, 6: 1, 7: 0.7, 8: 0.45, 9: 0.25, 10: 0.08, 11: 0.04, 12: 0.03])
            // Where winters are mild, plenty of birds stay and sing year-round.
            if [.subtropical, .mediterranean, .arid].contains(climate) { s = max(s, 0.3) }
            let darkWinter = climate == .subpolar && (m <= 2 || m >= 11)
            return darkWinter ? 0 : p * s
        // The cold months' birds: a few chickadees and jays, busiest late morning.
        case .winterBirds:
            guard !tropical else { return 0 }
            return by(0.8, 1, 0.4, 0) * month([9: 0.3, 10: 0.8, 11: 1, 12: 1, 1: 1, 2: 1, 3: 0.6])
        case .gulls:
            return by(0.8, 1, 0.6, 0.05)
        // Geese pass over now and then in migration season: a few minutes, twice an hour.
        case .geese:
            guard [12, 13, 41, 42].contains(t.minute) else { return 0 }
            return by(1, 0.7, 1, 0.1) * month([3: 0.8, 4: 0.5, 9: 0.3, 10: 1, 11: 0.8])
        case .jungleBirds:
            return by(1, 0.7, 0.5, 0)
        case .parrots:
            return by(1, 0.5, 0.9, 0)
        case .howlers:
            return by(1, 0.3, 0.6, 0.12)
        case .canopy:
            return by(0.5, 1, 0.4, 0)

        // Insects and frogs need warmth, and in temperate places, the right months.
        case .crickets:
            let p = by(0.3, 0.15, 0.8, 1)
            let warm = ramp(temp, 11, 18)
            if tropical { return p * warm }
            return p * warm * month([5: 0.1, 6: 0.4, 7: 0.8, 8: 1, 9: 1, 10: 0.6, 11: 0.15])
        case .cicadas:
            let p = by(0.2, 1, 0.5, 0)
            let hot = ramp(temp, 21, 26)
            if tropical { return p * hot }
            return p * hot * month([6: 0.5, 7: 1, 8: 1, 9: 0.35])
        case .frogs:
            let p = by(0.3, 0.05, 0.8, 1)
            let mild = ramp(temp, 6, 13)
            if tropical { return p * mild * wet }
            return p * mild * month([3: 0.4, 4: 1, 5: 1, 6: 0.8, 7: 0.6, 8: 0.4, 9: 0.15])
        // Spring peepers: the first sound of spring nights, from about 5°C.
        case .peepers:
            return by(0.2, 0.05, 0.9, 1) * ramp(temp, 4, 10) * month([3: 0.6, 4: 1, 5: 0.9, 6: 0.4])
        case .treeFrogs:
            let p = by(0.25, 0.05, 0.7, 1)
            let warm = ramp(temp, 16, 22)
            if tropical { return p * warm * wet }
            return p * warm * month([6: 0.6, 7: 0.8, 8: 0.8, 9: 0.4])

        // Night animals, with their seasons: owls court in winter, wolves howl most in winter,
        // loons call through the breeding summer and fall quiet before they leave.
        case .owls:
            let p = by(0.3, 0, 0.5, 1)
            if tropical { return p }
            return p * month([12: 1, 1: 1, 2: 1, 3: 0.8, 4: 0.8, 5: 0.8, 6: 0.6, 7: 0.6, 8: 0.6, 9: 0.85, 10: 0.85, 11: 0.85])
        case .wolves:
            return by(0.6, 0.1, 0.8, 1)
                * month([12: 1, 1: 1, 2: 1, 3: 0.6, 4: 0.6, 5: 0.6, 6: 0.35, 7: 0.35, 8: 0.35, 9: 0.7, 10: 0.7, 11: 0.7])
        case .loons:
            return by(1, 0.45, 1, 0.9) * month([4: 0.4, 5: 1, 6: 1, 7: 0.9, 8: 0.6, 9: 0.3, 10: 0.1])
        case .whales:
            guard let months = place?.seasonal[.whales] else { return 1 }
            return months.contains(t.month) ? 1 : 0

        // Trees, water and fire through the year.
        case .leaves:
            guard climate.deciduous else { return 1 }
            // Bare branches in winter; loud dry leaves in October.
            return month([12: 0.15, 1: 0.15, 2: 0.15, 3: 0.15, 4: 0.4, 5: 0.9, 6: 0.9, 7: 0.9, 8: 0.9, 9: 0.9, 10: 1.2, 11: 0.75])
        case .stream, .waterfall:
            let snowmelt = climate.hasSeasons && (m == 4 || m == 5) ? 1.25 : 1
            return snowmelt * (temp < -10 ? 0.5 : 1)
        case .lake:
            let frozen = climate.lakesFreeze && temp < -2 && (m == 12 || m <= 3)
            return frozen ? 0 : 1
        case .fire:
            guard temp < 14 else { return 0 }
            return (0.35 + 0.65 * ramp(14 - temp, 0, 12)) * by(0.8, 0.55, 1, 1)

        // People keep hours.
        case .cityHum, .rainyStreet:
            let curve: [Double] = [0.45, 0.4, 0.35, 0.35, 0.4, 0.55, 0.75, 1.05, 1.1, 0.95, 0.9, 0.9,
                                   0.9, 0.9, 0.9, 0.9, 0.95, 1.1, 1.05, 0.95, 0.85, 0.75, 0.65, 0.55]
            return curve[t.hour]
        case .cafe:
            switch t.hour {
            case 7: return 0.6
            case 8...19: return 1
            case 20, 21: return 0.7
            default: return 0
            }
        case .train:
            switch t.hour {
            case 0: return 0.3
            case 1...4: return 0
            case 5: return 0.4
            case 7...9, 17...19: return 1.1
            case 23: return 0.6
            default: return 1
            }
        case .bells:
            guard (8...20).contains(t.hour) else { return 0 }
            // Calling to Sunday morning services, otherwise just on the hour.
            if t.weekday == 1 && (8...11).contains(t.hour) && t.minute >= 50 { return 1 }
            return t.minute < 2 ? 0.8 : 0

        // Wind makes some places what they are, and rings the chimes.
        case .wind:
            return min(1.2, max(0.25, (c.windKMH - 8) / 25))
        case .chimes:
            return c.windKMH < 4 ? 0.35 : c.windKMH < 20 ? 1 : 1.2

        default:
            return 1
        }
    }

    /// How the weather right now changes one of a place's sounds.
    static func weatherFactor(for kind: SoundKind, in c: Conditions) -> Double {
        let heavy = c.isThunder || c.precipitationMM > 2.5
        let freezing = c.isSnow || c.temperatureC < 3
        let snowCover = c.isSnow || c.snowDepth > 0.05
        switch kind {
        // Birds and insects shelter from rain, and stop altogether in a downpour or the cold.
        case .birds, .jungleBirds, .parrots, .cicadas, .crickets, .howlers, .canopy:
            if freezing || heavy { return 0 }
            if c.isRaining { return 0.3 }
            if c.isFog { return 0.6 }
            return snowCover ? 0.5 : 1
        // Night animals call less in rain.
        case .owls, .wolves, .loons:
            return heavy ? 0.3 : c.isRaining ? 0.6 : 1
        // Winter birds don't mind the cold, but shelter from rain.
        case .winterBirds:
            return heavy ? 0 : c.isRaining ? 0.3 : c.isFog ? 0.6 : 1
        case .gulls:
            return heavy ? 0.4 : c.isRaining ? 0.7 : 1
        // Geese keep flying in weather, and honk more in fog.
        case .geese:
            return heavy ? 0.3 : c.isRaining ? 0.7 : 1
        case .peepers:
            return freezing ? 0 : c.isRaining ? 1.3 : 1
        // Frogs love rain; cold silences them.
        case .frogs, .treeFrogs:
            if freezing { return 0 }
            return c.isRaining ? 1.4 : 1
        // Wind roughens the water and stirs the trees; snow weighs the branches down.
        // Surf keeps rolling in calm air; a lake only laps when there's wind; leaves only rustle in a breeze.
        case .ocean:
            return c.windKMH < 10 ? 0.85 : c.windKMH > 30 ? 1.25 : 1
        case .lake:
            return c.windKMH < 5 ? 0.35 : c.windKMH < 15 ? 0.65 : c.windKMH > 30 ? 1.3 : 1
        case .leaves:
            let breeze = c.windKMH < 5 ? 0.4 : c.windKMH < 15 ? 0.7 : c.windKMH > 30 ? 1.4 : 1
            return c.isSnow ? breeze * 0.5 : breeze
        // Snow muffles a city; rain empties café terraces.
        case .cityHum, .rainyStreet, .train:
            return snowCover ? 0.65 : 1
        case .cafe:
            return heavy ? 0.5 : snowCover ? 0.6 : 1
        case .whales:
            return heavy ? 0.6 : 1
        default:
            return 1
        }
    }
}

// MARK: - The scene

enum Soundscape {
    /// What you'd hear at a place right now: its weather, then its own sounds in season.
    /// `playableOnly` swaps any recording the app doesn't have for its nearest stand-in.
    static func compose(_ c: Conditions, place: Place?, now: Date = Date(),
                        playableOnly: Bool = true) -> [(SoundKind, Double)] {
        var levels: [SoundKind: Double] = [:]
        func add(_ kind: SoundKind, _ level: Double) {
            guard level >= 0.05 else { return }
            levels[kind] = min(0.9, max(levels[kind] ?? 0, level))
        }

        // Weather you'd hear anywhere.
        if c.isRaining && !c.isSnow {
            switch c.rainIntensity {
            case .light: add(.lightRain, 0.6)
            case .moderate: add(.rain, min(0.85, 0.45 + c.precipitationMM / 6))
            case .heavy:
                add(.heavyRain, 0.8)
                add(.rain, 0.25)
            }
        }
        if c.isThunder {
            add(.thunder, 0.45)
            add(.lightning, 0.4)
        }
        // A breeze is heard through what it moves (leaves, water); real wind past about 18 km/h.
        if c.windKMH > 18 {
            add(.wind, min(0.8, (c.windKMH - 15) / 35) * (c.isSnow ? 0.7 : 1))
        }

        // The place itself, in season and at this hour.
        let cast = place?.signature ?? []
        let seasonal = (place?.climate ?? Climate.of(latitude: c.latitude)).hasSeasons
        func level(_ kind: SoundKind, _ base: Double) -> Double {
            base * 1.5 * Ecology.activity(of: kind, at: place, in: c, now: now) * Ecology.weatherFactor(for: kind, in: c)
        }
        for (kind, base) in cast {
            add(kind, level(kind, base))
            // Where there are seasons, a place's birds include the few that stay for winter.
            if kind == .birds && seasonal { add(.winterBirds, level(.winterBirds, base)) }
        }
        if c.isFog && cast.contains(where: { $0.0 == .ocean || $0.0 == .gulls }) {
            add(.foghorn, 0.4)
        }

        // Rain lands on what's there: a wet street in a city, a tin roof in a tropical town.
        if c.isRaining && !c.isSnow {
            if let city = levels.removeValue(forKey: .cityHum) { add(.rainyStreet, city) }
            let isCity = cast.contains { $0.0 == .cityHum && $0.1 >= 0.3 }
            let isForest = cast.contains { $0.0 == .canopy }
            if let place, abs(place.latitude) < 23.5, !isCity, !isForest {
                let rain = [SoundKind.rain, .lightRain].compactMap { levels.removeValue(forKey: $0) }.max() ?? 0.5
                add(.tinRoof, c.rainIntensity == .light ? 0.5 : rain)
            }
        }

        var result: [(SoundKind, Double)] = []
        for (kind, level) in levels {
            let k = playableOnly ? kind.playable : kind
            guard let k else { continue }
            if let i = result.firstIndex(where: { $0.0 == k }) {
                result[i].1 = max(result[i].1, level)
            } else {
                result.append((k, level))
            }
        }

        // Settle near a calm listening level, partway, so places still differ.
        result = Mix.balance(result)
        // Never quite silent: a soft hush beneath a very sparse scene, under it where it can be,
        // and only ever faint (-46 to -38 LUFS).
        let loudness = Mix.loudness(result)
        if loudness < Mix.target - 8 {
            let hush = max(Mix.target - 22, min(Mix.target - 14, loudness - 6))
            result.append((.brown, pow(10, (hush - Mix.reference - SoundKind.brown.presenceDB) / 20)))
        }
        return result.sorted { $0.1 > $1.1 }
    }
}
