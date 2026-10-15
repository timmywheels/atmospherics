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
    /// The local calendar at the place, from its UTC offset. An imagined scene can fix its hour
    /// and month (the minutes still tick, for the sounds that keep time).
    func localTime(at date: Date = Date()) -> (month: Int, weekday: Int, hour: Int, minute: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffset) ?? .gmt
        let c = calendar.dateComponents([.month, .weekday, .hour, .minute], from: date)
        return (forcedMonth ?? c.month ?? 1, c.weekday ?? 1, forcedHour ?? c.hour ?? 12, c.minute ?? 0)
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
        // A skein of geese passes over now and then in migration season: in about half the hours,
        // at a different minute each time.
        case .geese:
            let hour = Int(now.timeIntervalSince1970 / 3600)
            let seed = Self.seed("\(place?.name ?? "here")·geese")
            let start = 5 + Int(noise(seed, hour &* 31 &+ 7) * 50)
            guard noise(seed, hour) < 0.5, (start...start + 1).contains(t.minute) else { return 0 }
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
        case .rainyStreet:
            let curve: [Double] = [0.45, 0.4, 0.35, 0.35, 0.4, 0.55, 0.75, 1.05, 1.1, 0.95, 0.9, 0.9,
                                   0.9, 0.9, 0.9, 0.9, 0.95, 1.1, 1.05, 0.95, 0.85, 0.75, 0.65, 0.55]
            return curve[t.hour]
        // The day's hum thins out late, and the city at night (distant traffic, no bustle) takes over.
        case .cityHum:
            let curve: [Double] = [0.25, 0.2, 0.15, 0.15, 0.2, 0.45, 0.75, 1.05, 1.1, 0.95, 0.9, 0.9,
                                   0.9, 0.9, 0.9, 0.9, 0.95, 1.1, 1.05, 0.95, 0.8, 0.65, 0.5, 0.35]
            return curve[t.hour]
        case .cityNight:
            let curve: [Double] = [0.9, 0.95, 1, 1, 0.9, 0.6, 0.25, 0, 0, 0, 0, 0,
                                   0, 0, 0, 0, 0, 0, 0, 0.15, 0.35, 0.55, 0.75, 0.85]
            return curve[t.hour]
        case .cafe, .busyCafe:
            switch t.hour {
            case 7: return 0.6
            case 8...19: return 1
            case 20, 21: return 0.7
            default: return 0
            }
        case .train, .steamTrain, .electricTrain:
            switch t.hour {
            case 0: return 0.3
            case 1...4: return 0
            case 5: return 0.4
            case 7...9, 17...19: return 1.1
            case 23: return 0.6
            default: return 1
            }
        // Traffic swells at the rush hours and thins out after midnight; weekend mornings sleep in.
        case .traffic:
            let curve: [Double] = [0.3, 0.2, 0.12, 0.1, 0.15, 0.35, 0.7, 1.1, 1.15, 0.95, 0.85, 0.85,
                                   0.9, 0.85, 0.85, 0.9, 1, 1.15, 1.1, 0.9, 0.75, 0.6, 0.5, 0.4]
            let weekendMorning = (t.weekday == 1 || t.weekday == 7) && (6...10).contains(t.hour)
            return curve[t.hour] * (weekendMorning ? 0.6 : 1)
        // A highway never quite stops.
        case .highway:
            let curve: [Double] = [0.5, 0.4, 0.35, 0.35, 0.45, 0.65, 0.9, 1.1, 1.1, 1, 0.95, 0.95,
                                   0.95, 0.95, 0.95, 1, 1.05, 1.1, 1.05, 0.95, 0.85, 0.75, 0.65, 0.55]
            return curve[t.hour]
        // A plane passes over now and then: up to three an hour on a busy flight path, one an hour
        // elsewhere, each in a two-minute window long enough to hear it go by, at minutes of the
        // place's own so places don't all hear one at once. Airports rest in the small hours.
        case .planes:
            let busy = place?.signature.first { $0.0 == .planes }?.1 ?? 0.1
            let every = busy >= 0.25 ? 20 : busy >= 0.12 ? 30 : 60
            let shift = (place?.name.unicodeScalars.reduce(0) { $0 + Int($1.value) } ?? 0) % every
            guard (t.minute + 60 - shift) % every < 2 else { return 0 }
            switch t.hour {
            case 1...5: return 0
            case 0, 6, 23: return 0.5
            default: return 1
            }
        // A tram rattles past every so often while the trams run, each place at its own minutes.
        case .tram:
            guard (6...22).contains(t.hour) else { return 0 }
            let busy = place?.signature.first { $0.0 == .tram }?.1 ?? 0.1
            let every = busy >= 0.25 ? 12 : 20
            let shift = (place?.name.unicodeScalars.reduce(0) { $0 + Int($1.value) } ?? 0) % every
            return (t.minute + 60 - shift) % every < 2 ? 1 : 0
        // A temple bell sounds every two hours from dawn, as the hour turns.
        case .templeBell:
            return (6...20).contains(t.hour) && t.hour % 2 == 0 && t.minute < 2 ? 1 : 0
        case .motorbikes:
            let curve: [Double] = [0.35, 0.25, 0.15, 0.12, 0.2, 0.45, 0.8, 1.1, 1.15, 1, 0.9, 0.9,
                                   0.95, 0.9, 0.9, 0.95, 1.05, 1.15, 1.1, 0.95, 0.8, 0.65, 0.55, 0.45]
            return curve[t.hour]
        // Fountains run from morning to late evening; a market keeps market hours.
        case .fountain:
            return (6...23).contains(t.hour) ? 1 : 0.4
        case .bazaar:
            switch t.hour {
            case 9...21: return 1
            case 8, 22: return 0.5
            default: return 0
            }
        case .bells:
            guard (8...20).contains(t.hour) else { return 0 }
            // Calling to Sunday morning services, otherwise just on the hour.
            if t.weekday == 1 && (8...11).contains(t.hour) && t.minute >= 50 { return 1 }
            return t.minute < 2 ? 0.8 : 0

        // Wind makes some places what they are, and rings the chimes.
        case .wind, .treeWind, .gusts, .howl:
            return min(1.2, max(0.25, (c.windKMH - 8) / 25))
        // A breeze in the leaves, from the lightest air up to a fresh wind.
        case .breeze:
            return c.windKMH < 3 ? 0.3 : min(1, 0.45 + c.windKMH / 30)
        case .chimes:
            return c.windKMH < 4 ? 0.35 : c.windKMH < 20 ? 1 : 1.2

        default:
            return 1
        }
    }

    /// Scenes never sit still. Each of a place's living sounds wanders on its own slow path,
    /// closer and farther over several minutes, and now and then falls quiet for a while, so an
    /// hour in one place keeps changing. The air of a place (surf, rain, the city's hum, a stream)
    /// only breathes a little; events and sounds on a clock keep their own time. The path is
    /// seeded by the place and the sound, so it's the same on every device at the same moment.
    /// `steady` treats any sound as part of the air (an atmosphere's own sounds, like the fire in
    /// a cabin, shouldn't go quiet for a stretch).
    static func drift(of kind: SoundKind, at place: Place?, now: Date, steady: Bool = false) -> Double {
        let depth: Double, rests: Bool
        switch kind {
        case .planes, .geese, .tram, .templeBell, .bells, .foghorn, .thunder, .lightning, .whales:
            return 1
        case _ where steady:
            (depth, rests) = (0.15, false)
        case .ocean, .rain, .lightRain, .heavyRain, .tinRoof, .tentRain, .rainyStreet, .cityHum, .stream, .waterfall,
             .lake, .lapping, .shore, .rocks, .fountain, .wind, .treeWind, .gusts, .howl, .breeze, .highway, .cityNight, .cabin, .fan, .caveDrips, .drone, .brown, .pink, .white, .green, .grey, .blue, .violet:
            (depth, rests) = (0.15, false)
        default:
            (depth, rests) = (0.5, true)
        }
        let seed = Self.seed("\(place?.name ?? "here")·\(kind.rawValue)")
        let period = 4 + Double(seed % 6)   // minutes between turns
        let x = now.timeIntervalSince1970 / 60 / period
        let step = Int(x.rounded(.down)), f = x - x.rounded(.down)
        let s = f * f * (3 - 2 * f)
        let v = noise(seed, step) * (1 - s) + noise(seed, step + 1) * s   // 0…1, smooth
        let level = 1 - depth / 2 + depth * v
        // About one stretch in eight, a living sound rests.
        return rests ? level * min(1, max(0, (v - 0.04) / 0.12)) : level
    }

    private static func seed(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf29ce484222325) { ($0 ^ UInt64($1)) &* 0x100000001b3 }   // FNV-1a
    }

    /// A stable number in 0..<1 for a seed and a step (SplitMix64).
    private static func noise(_ seed: UInt64, _ step: Int) -> Double {
        var x = seed &+ UInt64(bitPattern: Int64(step)) &* 0x9E3779B97F4A7C15
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x ^= x >> 31
        return Double(x >> 11) / Double(UInt64(1) << 53)
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
        // Night animals call less in rain, and not at all in a thunderstorm (loons keep on).
        case .owls, .wolves:
            return c.isThunder ? 0 : heavy ? 0.3 : c.isRaining ? 0.6 : 1
        case .loons:
            return heavy ? 0.3 : c.isRaining ? 0.6 : 1
        // Winter birds don't mind the cold, but shelter from rain.
        case .winterBirds:
            return heavy ? 0 : c.isRaining ? 0.3 : c.isFog ? 0.6 : 1
        case .gulls:
            return c.isThunder ? 0 : heavy ? 0.4 : c.isRaining ? 0.7 : 1
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
        // Snow muffles a city; rain empties café terraces; wet roads hiss.
        case .cityHum, .cityNight, .rainyStreet, .train, .steamTrain, .electricTrain:
            return snowCover ? 0.65 : 1
        case .traffic:
            return snowCover ? 0.6 : 1
        case .highway:
            return snowCover ? 0.7 : c.isRaining ? 1.15 : 1
        case .planes:
            return heavy ? 0.5 : 1
        // Fewer riders in the rain; fountains are drained in a freeze; markets thin out in a downpour.
        case .motorbikes:
            return heavy ? 0.5 : c.isRaining ? 0.8 : 1
        case .fountain:
            return c.temperatureC < 1 ? 0 : 1
        case .bazaar:
            return heavy ? 0.6 : 1
        case .cafe, .busyCafe:
            return heavy ? 0.5 : snowCover ? 0.6 : 1
        case .whales:
            return heavy ? 0.6 : 1
        // Calm water laps; wind turns it into surf. Swell pounds the rocks harder in wind.
        case .lapping, .shore:
            return c.windKMH < 20 ? 1 : c.windKMH < 35 ? 0.85 : 0.6
        case .rocks:
            return c.windKMH < 10 ? 0.85 : c.windKMH > 30 ? 1.25 : 1
        // Palm fronds and a harbor's rigging only talk in a breeze.
        case .palms, .halyards:
            return c.windKMH < 8 ? 0.3 : c.windKMH < 18 ? 0.7 : c.windKMH > 30 ? 1.3 : 1
        // A bell buoy rocks with the swell, and carries best in fog.
        case .buoy:
            return (c.windKMH < 10 ? 0.6 : c.windKMH > 25 ? 1.2 : 1) * (c.isFog ? 1.2 : 1)
        default:
            return 1
        }
    }
}

// MARK: - The scene

enum Soundscape {
    /// What you'd hear at a place right now: its weather, then its own sounds in season.
    /// `playableOnly` swaps any recording the app doesn't have for its nearest stand-in.
    /// For an atmosphere, `core` sounds are always there whatever the hour or weather (a café's
    /// room is open at midnight), rain can land on a surface of its own (a tent), and indoors the
    /// weather is `muffle`d by the walls.
    static func compose(_ c: Conditions, place: Place?, now: Date = Date(), playableOnly: Bool = true,
                        core: Set<SoundKind> = [], rainOn surface: SoundKind? = nil,
                        muffle: Double = 1, wind windKind: SoundKind = .wind) -> [(SoundKind, Double)] {
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
        // A breeze is heard through what it moves (leaves, water); wind past about 18 km/h, of the
        // place's own kind (in the trees, at the window), and in gusts when it snows outdoors. In the
        // open it comes in levels: a steady breeze in a moderate wind, the rise and fall of real
        // wind past about 30 km/h, and gusts on top past 45.
        if c.windKMH > 18 {
            let level = min(0.8, (c.windKMH - 15) / 35) * (c.isSnow ? 0.7 : 1)
            if c.isSnow && windKind != .howl {
                add(.gusts, level)
            } else if windKind == .wind {
                if c.windKMH < 30 {
                    // The breeze sits further back than wind (`presenceDB`): brought up to meet it.
                    add(.breeze, min(0.8, 0.25 + level * 1.6))
                } else {
                    add(.wind, level)
                    if c.windKMH > 45 { add(.gusts, level * 0.6) }
                }
            } else {
                add(windKind, level)
            }
        }

        // The place itself, in season and at this hour.
        let cast = place?.signature ?? []
        let seasonal = (place?.climate ?? Climate.of(latitude: c.latitude)).hasSeasons
        func level(_ kind: SoundKind, _ base: Double) -> Double {
            if core.contains(kind) { return base * 1.5 * Ecology.drift(of: kind, at: place, now: now, steady: true) }
            return base * 1.5 * Ecology.activity(of: kind, at: place, in: c, now: now) * Ecology.weatherFactor(for: kind, in: c)
                * Ecology.drift(of: kind, at: place, now: now)
        }
        for (kind, base) in cast {
            add(kind, level(kind, base))
            // Where there are seasons, a place's birds include the few that stay for winter.
            if kind == .birds && seasonal { add(.winterBirds, level(.winterBirds, base)) }
            // A city's hum gives way to the city at night.
            if kind == .cityHum { add(.cityNight, level(.cityNight, base)) }
        }
        if c.isFog && cast.contains(where: { [.ocean, .rocks, .gulls, .buoy].contains($0.0) }) {
            add(.foghorn, 0.4)
        }

        // Rain lands on what's there: a wet street in a city, a tin roof in a tropical town.
        if c.isRaining && !c.isSnow {
            if let city = levels.removeValue(forKey: .cityHum) { add(.rainyStreet, city) }
            if let night = levels.removeValue(forKey: .cityNight) { add(.rainyStreet, night) }
            if let cars = levels.removeValue(forKey: .traffic) { add(.rainyStreet, cars) }
            let isCity = cast.contains { $0.0 == .cityHum && $0.1 >= 0.3 }
            let isForest = cast.contains { $0.0 == .canopy }
            if let surface {
                let rain = [SoundKind.rain, .lightRain, .heavyRain].compactMap { levels.removeValue(forKey: $0) }.max() ?? 0.5
                add(surface, rain)
            } else if let place, abs(place.latitude) < 23.5, !isCity, !isForest {
                let rain = [SoundKind.rain, .lightRain].compactMap { levels.removeValue(forKey: $0) }.max() ?? 0.5
                add(.tinRoof, c.rainIntensity == .light ? 0.5 : rain)
            }
        }

        if muffle < 1 {
            // Walls stop the hiss of rain more than the low roar of wind and thunder.
            for kind in [SoundKind.rain, .lightRain, .heavyRain] {
                if let level = levels[kind] { levels[kind] = level * muffle }
            }
            // (A howl is what's heard inside already.)
            for kind in [SoundKind.wind, .treeWind, .gusts, .breeze, .thunder, .lightning] {
                if let level = levels[kind] { levels[kind] = level * muffle.squareRoot() }
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
