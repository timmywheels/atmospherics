import Foundation

// Atmospheres: the scenes people ask for by name ("a log cabin in a snowstorm", "a rainy day in
// the city") rather than by country. Each is a setting, its weather and a time of day. They play
// through the same ecology as the real places (dawn brings birds, the city quiets after midnight),
// and when it's really like that somewhere right now, they take that place's live weather.

/// The weather in an atmosphere.
enum Sky: String, CaseIterable, Codable {
    case clear, wind, fog, drizzle, rain, downpour, thunderstorm, snow, snowstorm

    /// For menus and chips.
    var name: String {
        switch self {
        case .clear: "Clear"
        case .wind: "Windy"
        case .fog: "Fog"
        case .drizzle: "Light rain"
        case .rain: "Rain"
        case .downpour: "Downpour"
        case .thunderstorm: "Thunderstorm"
        case .snow: "Snow"
        case .snowstorm: "Snowstorm"
        }
    }

    /// In a sentence: "Take me to a log cabin in a snowstorm".
    var phrase: String {
        switch self {
        case .clear: "under clear skies"
        case .wind: "in the wind"
        case .fog: "in the fog"
        case .drizzle: "in light rain"
        case .rain: "in the rain"
        case .downpour: "in a downpour"
        case .thunderstorm: "in a thunderstorm"
        case .snow: "in the snow"
        case .snowstorm: "in a snowstorm"
        }
    }

    /// For names led by the weather, "A rainy night in the city". The rest lead with the
    /// setting: "A tent in a thunderstorm".
    var adjective: String? {
        switch self {
        case .wind: "windy"
        case .fog: "foggy"
        case .rain: "rainy"
        case .snow: "snowy"
        default: nil
        }
    }

    /// Whether a place's live weather is this.
    func matches(_ c: Conditions) -> Bool {
        let rain = c.isRaining && !c.isSnow && !c.isThunder
        switch self {
        case .clear: return !c.isRaining && !c.isSnow && !c.isFog && c.windKMH < 30 && c.code <= 3
        case .wind: return c.windKMH >= 30 && !c.isRaining && !c.isSnow
        case .fog: return c.isFog && !c.isRaining
        case .drizzle: return rain && c.rainIntensity == .light
        case .rain: return rain && c.rainIntensity == .moderate
        case .downpour: return rain && c.rainIntensity == .heavy
        case .thunderstorm: return c.isThunder
        case .snow: return c.isSnow && c.windKMH < 30
        case .snowstorm: return c.isSnow && c.windKMH >= 30
        }
    }

    /// "Snowing in Lofoten right now".
    func live(in place: String) -> String {
        switch self {
        case .clear: "Clear skies over \(place) right now"
        case .wind: "Windy in \(place) right now"
        case .fog: "Foggy in \(place) right now"
        case .drizzle: "Light rain in \(place) right now"
        case .rain: "Raining in \(place) right now"
        case .downpour: "Pouring in \(place) right now"
        case .thunderstorm: "A thunderstorm over \(place) right now"
        case .snow: "Snowing in \(place) right now"
        case .snowstorm: "A snowstorm in \(place) right now"
        }
    }

    /// The weather as Open-Meteo would report it, for an imagined scene.
    fileprivate var imagined: (code: Int, rain: Double, wind: Double, snow: Double, pressure: Double) {
        switch self {
        case .clear: (1, 0, 8, 0, 1018)
        case .wind: (3, 0, 42, 0, 1004)
        case .fog: (45, 0, 4, 0, 1016)
        case .drizzle: (53, 0.3, 10, 0, 1010)
        case .rain: (63, 1.8, 14, 0, 1006)
        case .downpour: (65, 7, 18, 0, 1002)
        case .thunderstorm: (95, 5, 30, 0, 996)
        case .snow: (73, 0, 10, 0.2, 1012)
        case .snowstorm: (75, 0, 48, 0.4, 998)
        }
    }

    /// Snow belongs to winter and thunderstorms to summer, whatever the month.
    fileprivate var month: Int? {
        switch self {
        case .snow, .snowstorm: 1
        case .thunderstorm: 7
        default: nil
        }
    }
}

/// When an atmosphere is set. `now` follows your clock.
enum TimeOfDay: String, CaseIterable, Codable {
    case now, dawn, day, dusk, night

    var name: String {
        switch self {
        case .now: "Right now"
        case .dawn: "Dawn"
        case .day: "Day"
        case .dusk: "Dusk"
        case .night: "Night"
        }
    }

    /// In a sentence: "… at night".
    var phrase: String {
        switch self {
        case .now: "right now"
        case .dawn: "at dawn"
        case .day: "by day"
        case .dusk: "at dusk"
        case .night: "at night"
        }
    }

    var phase: DayPhase? {
        switch self {
        case .now: nil
        case .dawn: .dawn
        case .day: .day
        case .dusk: .dusk
        case .night: .night
        }
    }

    /// The hour an imagined scene is set at.
    fileprivate var hour: Int? {
        switch self {
        case .now: nil
        case .dawn: 6
        case .day: 13
        case .dusk: 19
        case .night: 23
        }
    }
}

/// Where an atmosphere is: what you'd hear there, and what weather and times suit it.
enum Setting: String, CaseIterable, Codable {
    case cabin, city, cafe, beach, tent, forest, jungle, lake, harbor, train, library, temple, mountains, tinRoof, porch, market, flight

    struct Info {
        /// For chips: "Log cabin".
        let name: String
        /// Where a sentence takes you: "to a log cabin", "under a tin roof".
        let go: String
        /// Leading a name: "A log cabin (in a snowstorm)".
        let lead: String
        /// Ending a name: "(A rainy night) in a log cabin".
        let at: String
        /// Indoors, a clear day is "quiet" rather than "sunny".
        let indoors: Bool
        /// What you could hear there, like a place's cast; `Ecology` decides what's out right now.
        let signature: [(SoundKind, Double)]
        /// Sounds that make it what it is, there whatever the hour or the weather.
        let core: Set<SoundKind>
        let climate: Climate
        let latitude: Double
        /// The month it's set in when the weather doesn't say: summer for a porch, winter for a cabin.
        let month: Int?
        let skies: [Sky]
        let times: [TimeOfDay]
        /// Under the name, when it isn't live from anywhere.
        let line: String
        /// Rain lands on something of its own here.
        let rainOn: SoundKind?
        /// Which real places it could be live from, besides having the weather. Nil: none.
        let suits: ((Place, Conditions) -> Bool)?
        /// Indoors, the weather outside is heard through the walls: rain and wind this much quieter.
        var muffle: Double = 1
        /// What wind sounds like here: open air, in the trees, mountain gusts, or a howl at the window.
        var wind: SoundKind = .wind
    }

    var info: Info { Self.infos[self]! }

    private static let infos = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.makeInfo()) })

    private func makeInfo() -> Info {
        func has(_ p: Place, _ kind: SoundKind, _ level: Double = 0.01) -> Bool {
            p.signature.contains { $0.0 == kind && $0.1 >= level }
        }
        let all = TimeOfDay.allCases
        switch self {
        case .cabin:
            return Info(name: "Log cabin", go: "to a log cabin", lead: "A log cabin", at: "in a log cabin", indoors: true,
                        signature: [(.fire, 0.5), (.howl, 0.12), (.clock, 0.2), (.owls, 0.15), (.wolves, 0.1), (.leaves, 0.08)],
                        core: [.fire], climate: .continental, latitude: 46, month: 1,
                        skies: [.snowstorm, .snow, .rain, .thunderstorm, .wind, .fog, .clear], times: all,
                        line: "A fire going, the weather outside", rainOn: nil,
                        suits: { p, c in c.temperatureC < 12 && p.climate != .tropical && !has(p, .cityHum, 0.3) }, muffle: 0.5,
                        wind: .howl)
        case .city:
            return Info(name: "City", go: "to the city", lead: "The city", at: "in the city", indoors: false,
                        signature: [(.cityHum, 0.45), (.traffic, 0.3), (.tram, 0.15), (.bells, 0.1), (.cafe, 0.12),
                                    (.planes, 0.08), (.highway, 0.08), (.birds, 0.08)],
                        core: [], climate: .temperate, latitude: 45, month: nil,
                        skies: [.rain, .drizzle, .downpour, .thunderstorm, .snow, .fog, .wind, .clear], times: all,
                        line: "Streets, traffic and the city's hum", rainOn: nil,
                        suits: { p, _ in has(p, .cityHum, 0.3) })
        case .cafe:
            return Info(name: "Café", go: "to a café", lead: "A café", at: "in a café", indoors: true,
                        signature: [(.cafe, 0.55), (.cityHum, 0.12), (.traffic, 0.08)],
                        core: [.cafe], climate: .temperate, latitude: 45, month: nil,
                        skies: [.rain, .drizzle, .downpour, .snow, .fog, .clear], times: all,
                        line: "Cups, chatter and the street outside", rainOn: nil,
                        suits: { p, _ in has(p, .cafe) || has(p, .cityHum, 0.3) }, muffle: 0.45)
        case .beach:
            return Info(name: "Beach", go: "to the beach", lead: "The beach", at: "at the beach", indoors: false,
                        signature: [(.ocean, 0.5), (.lapping, 0.25), (.gulls, 0.2), (.palms, 0.15), (.crickets, 0.15), (.wind, 0.1)],
                        core: [], climate: .subtropical, latitude: 28, month: 8,
                        skies: [.clear, .wind, .fog, .drizzle, .rain, .thunderstorm], times: all,
                        line: "Waves rolling in", rainOn: nil,
                        suits: { p, _ in has(p, .ocean, 0.3) || has(p, .lapping, 0.3) })
        case .tent:
            return Info(name: "Tent", go: "to a tent", lead: "A tent", at: "in a tent", indoors: true,
                        signature: [(.leaves, 0.2), (.owls, 0.15), (.crickets, 0.15), (.stream, 0.15), (.birds, 0.15), (.frogs, 0.08)],
                        core: [], climate: .temperate, latitude: 44, month: 7,
                        skies: [.rain, .thunderstorm, .downpour, .drizzle, .wind, .fog, .clear], times: all,
                        line: "The woods all around, close by", rainOn: .tentRain,
                        suits: { p, c in c.temperatureC > 4 && (has(p, .leaves, 0.15) || has(p, .owls)) && !has(p, .cityHum, 0.3) },
                        wind: .treeWind)
        case .forest:
            return Info(name: "Forest", go: "to the forest", lead: "The forest", at: "in the forest", indoors: false,
                        signature: [(.leaves, 0.35), (.birds, 0.3), (.stream, 0.2), (.owls, 0.2), (.breeze, 0.15),
                                    (.frogs, 0.08), (.crickets, 0.08), (.geese, 0.05)],
                        core: [], climate: .temperate, latitude: 46, month: 5,
                        skies: [.clear, .rain, .drizzle, .fog, .snow, .wind, .thunderstorm], times: all,
                        line: "Trees, birdsong and a stream", rainOn: nil,
                        suits: { p, _ in has(p, .leaves, 0.2) && !has(p, .cityHum, 0.3) }, wind: .treeWind)
        case .jungle:
            return Info(name: "Jungle", go: "to the jungle", lead: "The jungle", at: "in the jungle", indoors: false,
                        signature: [(.canopy, 0.4), (.jungleBirds, 0.35), (.howlers, 0.25), (.parrots, 0.2), (.treeFrogs, 0.3),
                                    (.stream, 0.15), (.cicadas, 0.12)],
                        core: [], climate: .tropical, latitude: 4, month: nil,
                        skies: [.clear, .rain, .downpour, .thunderstorm, .fog, .drizzle], times: all,
                        line: "The rainforest, wide awake", rainOn: nil,
                        suits: { p, _ in has(p, .canopy) || has(p, .jungleBirds, 0.3) }, wind: .treeWind)
        case .lake:
            return Info(name: "Lake", go: "to the lake", lead: "The lake", at: "at the lake", indoors: false,
                        signature: [(.lake, 0.4), (.loons, 0.4), (.peepers, 0.25), (.frogs, 0.25), (.crickets, 0.2),
                                    (.owls, 0.1), (.geese, 0.08), (.leaves, 0.1)],
                        core: [], climate: .continental, latitude: 45, month: 6,
                        skies: [.clear, .fog, .drizzle, .rain, .wind, .thunderstorm, .snow], times: all,
                        line: "Still water, loons across it", rainOn: nil,
                        suits: { p, _ in has(p, .lake, 0.3) || has(p, .loons) }, wind: .treeWind)
        case .harbor:
            return Info(name: "Harbor", go: "to a harbor", lead: "A harbor", at: "at the harbor", indoors: false,
                        signature: [(.halyards, 0.35), (.buoy, 0.3), (.lapping, 0.3), (.gulls, 0.3), (.rocks, 0.12),
                                    (.ocean, 0.1), (.bells, 0.05)],
                        core: [], climate: .temperate, latitude: 42, month: nil,
                        skies: [.fog, .wind, .clear, .drizzle, .rain, .thunderstorm, .snow], times: all,
                        line: "Rigging, a bell buoy, gulls", rainOn: nil,
                        suits: { p, _ in has(p, .halyards) || has(p, .buoy) || has(p, .gulls, 0.2) })
        case .train:
            return Info(name: "Sleeper train", go: "on a sleeper train", lead: "A sleeper train", at: "on a sleeper train",
                        indoors: true, signature: [(.train, 0.6)], core: [.train], climate: .temperate, latitude: 45, month: nil,
                        skies: [.rain, .snow, .snowstorm, .clear, .thunderstorm, .fog], times: all,
                        line: "The rhythm of the rails", rainOn: nil,
                        suits: { p, _ in p.climate != .tropical }, muffle: 0.5, wind: .howl)
        case .library:
            return Info(name: "Library", go: "to a library", lead: "A library", at: "in a library", indoors: true,
                        signature: [(.library, 0.5), (.clock, 0.35), (.fire, 0.18), (.cityHum, 0.06)],
                        core: [.library, .clock], climate: .temperate, latitude: 45, month: nil,
                        skies: [.rain, .drizzle, .snow, .thunderstorm, .clear, .fog], times: [.now, .day, .dusk, .night],
                        line: "Quiet pages, a clock, soft footsteps", rainOn: nil,
                        suits: { _, _ in true }, muffle: 0.4, wind: .howl)
        case .temple:
            return Info(name: "Temple garden", go: "to a temple garden", lead: "A temple garden", at: "in a temple garden",
                        indoors: false,
                        signature: [(.templeBell, 0.35), (.fountain, 0.25), (.stream, 0.2), (.birds, 0.25), (.chimes, 0.12), (.leaves, 0.15),
                                    (.breeze, 0.1)],
                        core: [], climate: .subtropical, latitude: 35, month: 4,
                        skies: [.drizzle, .rain, .clear, .fog, .snow], times: all,
                        line: "A fountain, a bell, the garden", rainOn: nil,
                        suits: { p, _ in has(p, .templeBell) }, wind: .treeWind)
        case .mountains:
            return Info(name: "Mountains", go: "to the mountains", lead: "The mountains", at: "in the mountains", indoors: false,
                        signature: [(.gusts, 0.35), (.stream, 0.25), (.waterfall, 0.15), (.wolves, 0.1), (.birds, 0.1), (.leaves, 0.08)],
                        core: [], climate: .subpolar, latitude: 47, month: nil,
                        skies: [.wind, .snow, .snowstorm, .clear, .fog, .rain, .thunderstorm], times: all,
                        line: "Wind over the ridges, water below", rainOn: nil,
                        suits: { p, _ in has(p, .wind, 0.3) && !has(p, .cityHum, 0.2) }, wind: .gusts)
        case .tinRoof:
            return Info(name: "Tin roof", go: "under a tin roof", lead: "Under a tin roof", at: "under a tin roof", indoors: true,
                        signature: [(.frogs, 0.3), (.treeFrogs, 0.25), (.crickets, 0.2), (.palms, 0.12)],
                        core: [], climate: .tropical, latitude: 10, month: nil,
                        skies: [.rain, .downpour, .thunderstorm, .drizzle], times: all,
                        line: "Rain drumming overhead", rainOn: .tinRoof,
                        suits: { p, _ in abs(p.latitude) < 23.5 && !has(p, .cityHum, 0.3) })
        case .porch:
            return Info(name: "Summer porch", go: "to a summer porch", lead: "A summer porch", at: "on a summer porch",
                        indoors: false,
                        signature: [(.crickets, 0.45), (.frogs, 0.3), (.cicadas, 0.25), (.chimes, 0.2), (.peepers, 0.15),
                                    (.leaves, 0.15), (.birds, 0.1), (.breeze, 0.12)],
                        core: [], climate: .subtropical, latitude: 36, month: 7,
                        skies: [.clear, .thunderstorm, .rain, .drizzle], times: all,
                        line: "Crickets, frogs and wind chimes", rainOn: nil,
                        suits: { p, c in c.temperatureC >= 18 && has(p, .crickets, 0.15) }, wind: .treeWind)
        case .market:
            return Info(name: "Market", go: "to the market", lead: "The market", at: "at the market", indoors: false,
                        signature: [(.bazaar, 0.5), (.motorbikes, 0.2), (.fountain, 0.12), (.cafe, 0.12), (.bells, 0.05)],
                        core: [.bazaar], climate: .arid, latitude: 31, month: nil,
                        skies: [.clear, .wind, .drizzle, .rain], times: [.now, .dawn, .day, .dusk],
                        line: "Stalls, voices, scooters passing", rainOn: nil,
                        suits: { p, _ in has(p, .bazaar) })
        case .flight:
            return Info(name: "Long flight", go: "on a long flight", lead: "A long flight", at: "on a long flight", indoors: true,
                        signature: [(.cabin, 0.6), (.brown, 0.18)], core: [.cabin, .brown], climate: .temperate, latitude: 45, month: nil,
                        skies: [.clear], times: all,
                        line: "The steady hum of the cabin, far above the weather", rainOn: nil,
                        suits: nil)
        }
    }

    /// The setting as a place for the ecology, with its own name so its sounds drift on paths of their own.
    var place: Place {
        let i = info
        return Place(name: "atmosphere.\(rawValue)", country: "", region: .yours, latitude: i.latitude, longitude: 0,
                     signature: i.signature, climate: i.climate)
    }
}

/// A scene by name: a setting, its weather and the time of day.
struct Atmosphere: Hashable, Codable, Identifiable {
    var setting: Setting
    var sky: Sky
    var time: TimeOfDay

    init(_ setting: Setting, _ sky: Sky, _ time: TimeOfDay = .now) {
        self.setting = setting
        self.sky = setting.info.skies.contains(sky) ? sky : setting.info.skies[0]
        self.time = setting.info.times.contains(time) ? time : .now
    }

    var id: String { "\(setting.rawValue).\(sky.rawValue).\(time.rawValue)" }

    /// Where changes you make to it in Layers are kept.
    var tweakKey: String { "atmosphere:\(id)" }

    /// "Take me to a log cabin in a snowstorm right now", in its three parts.
    var sentence: (setting: String, sky: String, time: String) { (setting.info.go, sky.phrase, time.phrase) }

    // MARK: Its name

    /// The name in one or two lines, following the hour when its time is "now":
    /// ["A log cabin", "in a snowstorm"], ["A rainy night", "in the city"], ["Dawn", "in the jungle"].
    func lines(in c: Conditions, at now: Date = Date()) -> [String] {
        let info = setting.info
        let phase = time.phase ?? c.phase(at: now)
        if setting == .flight {
            switch phase {
            case .dawn: return ["A flight at dawn"]
            case .day: return ["A long flight"]
            case .dusk: return ["An evening flight"]
            case .night: return ["A night flight"]
            }
        }
        let when: String = {
            if time == .day { return "day" }
            switch phase {
            case .dawn: return "dawn"
            case .day: return c.localTime(at: now).hour < 12 ? "morning" : "afternoon"
            case .dusk: return "evening"
            case .night: return "night"
            }
        }()
        if let adjective = sky.adjective {
            return ["A \(adjective) \(when)", info.at]
        }
        if sky == .clear {
            switch phase {
            case .dawn: return ["Dawn", info.at]
            case .dusk: return ["Dusk", info.at]
            case .night: return ["Night", info.at]
            case .day: return ["A \(info.indoors ? "quiet" : "sunny") \(when)", info.at]
            }
        }
        return [info.lead, time == .now ? sky.phrase : "\(sky.phrase) \(time.phrase)"]
    }

    func title(in c: Conditions, at now: Date = Date()) -> String { lines(in: c, at: now).joined(separator: " ") }

    // MARK: Its weather

    /// A real place where it's like this right now, if there is one: the right weather (and time
    /// of day, if it's set), somewhere that suits the setting. The same pick all hour, so it doesn't flit.
    func liveSource(among places: [Place], conditions: [String: Conditions], now: Date = Date()) -> (place: Place, conditions: Conditions)? {
        guard let suits = setting.info.suits else { return nil }
        let candidates = places.compactMap { p -> (Place, Conditions)? in
            guard let c = conditions[p.name], sky.matches(c), suits(p, c) else { return nil }
            if let phase = time.phase, c.phase(at: now) != phase { return nil }
            return (p, c)
        }
        guard !candidates.isEmpty else { return nil }
        let hour = Int(now.timeIntervalSince1970 / 3600)
        func rank(_ p: Place) -> UInt64 { "\(id)·\(p.name)·\(hour)".utf8.reduce(0xcbf29ce484222325) { ($0 ^ UInt64($1)) &* 0x100000001b3 } }
        return candidates.min { rank($0.0) < rank($1.0) }
    }

    /// The scene as weather, when it isn't live from anywhere: its sky, in its season, at its
    /// hour or on your clock.
    func imagined(now: Date = Date()) -> Conditions {
        let info = setting.info
        let w = sky.imagined
        let month = sky.month ?? info.month ?? Calendar.current.component(.month, from: now)
        let seasons = info.climate.hasSeasons
        let winter = [12, 1, 2].contains(month), summer = [6, 7, 8].contains(month)
        var temp: Double = {
            switch info.climate {
            case .tropical: 27
            case .arid: 24
            case .subtropical: 21
            case .mediterranean: 18
            case .temperate: 14
            case .continental: 10
            case .subpolar: 6
            }
        }()
        if seasons { temp += winter ? -9 : summer ? 7 : 0 }
        switch sky {
        case .snow: temp = min(temp, -3)
        case .snowstorm: temp = min(temp, -8)
        case .rain, .drizzle, .downpour: temp -= seasons ? 3 : 2
        case .fog, .wind: temp -= 3
        case .thunderstorm: temp = max(temp, 23)
        case .clear: break
        }
        // A day of the length the season gives.
        let sunrise: Int = winter ? 435 : summer ? 330 : 405     // 7:15, 5:30, 6:45
        let sunset: Int = winter ? 1005 : summer ? 1200 : 1095   // 16:45, 20:00, 18:15
        var c = Conditions(place: "", temperatureC: temp, precipitationMM: w.rain, windKMH: w.wind, pressureHPA: w.pressure,
                           code: w.code, isDay: true, latitude: info.latitude,
                           utcOffset: TimeZone.current.secondsFromGMT(for: now),
                           sunrise: sunrise, sunset: sunset, snowDepth: w.snow,
                           forcedPhase: time.phase, forcedHour: time.hour, forcedMonth: month)
        let phase = c.phase(at: now)
        c.isDay = phase == .dawn || phase == .day
        return c
    }

    /// What you'd hear, in these conditions.
    func mix(in c: Conditions, now: Date = Date(), playableOnly: Bool = true) -> [(SoundKind, Double)] {
        let info = setting.info
        return Soundscape.compose(c, place: setting.place, now: now, playableOnly: playableOnly,
                                  core: info.core, rainOn: info.rainOn, muffle: info.muffle, wind: info.wind)
    }

    // MARK: Picking one

    /// Hand-picked, for swiping through and for ideas.
    static let curated: [Atmosphere] = [
        Atmosphere(.cabin, .snowstorm),
        Atmosphere(.city, .rain),
        Atmosphere(.beach, .clear, .night),
        Atmosphere(.tent, .thunderstorm),
        Atmosphere(.cafe, .rain),
        Atmosphere(.train, .rain, .night),
        Atmosphere(.harbor, .fog, .dawn),
        Atmosphere(.jungle, .clear, .dawn),
        Atmosphere(.lake, .clear, .dusk),
        Atmosphere(.forest, .rain),
        Atmosphere(.library, .snow),
        Atmosphere(.porch, .thunderstorm),
        Atmosphere(.tinRoof, .downpour),
        Atmosphere(.mountains, .wind, .night),
        Atmosphere(.temple, .drizzle),
        Atmosphere(.market, .clear, .day),
        Atmosphere(.city, .snow, .night),
        Atmosphere(.flight, .clear, .night),
        Atmosphere(.beach, .thunderstorm),
        Atmosphere(.cabin, .rain, .night),
        Atmosphere(.jungle, .downpour),
        Atmosphere(.harbor, .wind),
        Atmosphere(.tent, .rain, .night),
        Atmosphere(.forest, .fog, .dawn),
        Atmosphere(.lake, .rain),
        Atmosphere(.train, .snow, .night),
        Atmosphere(.cafe, .snow),
        Atmosphere(.porch, .clear, .night),
    ]

    /// Any setting, in weather that suits it, mostly on your clock.
    /// The symbol for Surprise me, wherever it's offered.
    static let surpriseSymbol = "shuffle"

    static func random() -> Atmosphere {
        let setting = Setting.allCases.randomElement()!
        let info = setting.info
        let time: TimeOfDay = Double.random(in: 0..<1) < 0.7 ? .now : info.times.filter { $0 != .now }.randomElement() ?? .now
        return Atmosphere(setting, info.skies.randomElement()!, time)
    }

    // MARK: From words

    /// Reads "take me to a log cabin in a snowstorm at night" into an atmosphere. Settings are
    /// found first, so "rainforest" isn't read as rain. Weather a setting can't have becomes the
    /// nearest it can; with no setting, it picks one that suits the weather.
    static func parse(_ text: String) -> Atmosphere? {
        var t = " " + text.lowercased().replacingOccurrences(of: "’", with: "'") + " "
        func take<T>(_ table: [(T, [String])]) -> T? {
            let words = table.flatMap { entry in entry.1.map { (entry.0, $0) } }.sorted { $0.1.count > $1.1.count }
            for (value, word) in words {
                if let range = t.range(of: word) {
                    t.replaceSubrange(range, with: " ")
                    return value
                }
            }
            return nil
        }
        let setting = take(settingWords)
        let sky = take(skyWords)
        let time = take(timeWords) ?? .now
        guard setting != nil || sky != nil else { return nil }
        if let setting {
            let skies = setting.info.skies
            let chosen = sky.flatMap { s in skies.contains(s) ? s : nearest(s, in: skies) } ?? skies[0]
            return Atmosphere(setting, chosen, time)
        }
        guard let sky else { return nil }
        let options = Setting.allCases.filter { $0 != .flight && $0.info.skies.contains(sky) }
        return Atmosphere(options.randomElement() ?? .cabin, sky, time)
    }

    private static func nearest(_ sky: Sky, in skies: [Sky]) -> Sky? {
        let order: [Sky: [Sky]] = [
            .snowstorm: [.snow, .wind, .thunderstorm, .rain], .snow: [.snowstorm, .fog, .drizzle, .rain],
            .thunderstorm: [.downpour, .rain, .wind], .downpour: [.rain, .thunderstorm, .drizzle],
            .rain: [.drizzle, .downpour, .thunderstorm], .drizzle: [.rain, .fog], .fog: [.drizzle, .clear],
            .wind: [.clear, .fog], .clear: [.fog, .wind],
        ]
        return order[sky]?.first { skies.contains($0) }
    }

    private static let settingWords: [(Setting, [String])] = [
        (.cabin, ["log cabin", "cabin", "lodge", "chalet", "fireplace", "fireside", "fire"]),
        (.city, ["city", "street", "downtown", "town", "apartment", "urban"]),
        (.cafe, ["café", "cafe", "coffee shop", "coffee"]),
        (.beach, ["beach", "seaside", "shore", "coast", "ocean", "sea"]),
        (.tent, ["tent", "camping", "campsite", "camp"]),
        (.forest, ["forest", "woods", "woodland", "trees"]),
        (.jungle, ["jungle", "rainforest", "rain forest", "tropics", "amazon"]),
        (.lake, ["lake", "lakeside", "pond", "loons"]),
        (.harbor, ["harbor", "harbour", "marina", "port", "dock", "sailboats", "boats"]),
        (.train, ["sleeper train", "night train", "train", "railway"]),
        (.library, ["library", "reading room", "books", "study"]),
        (.temple, ["temple", "shrine", "zen garden", "monastery", "garden"]),
        (.mountains, ["mountains", "mountain", "peak", "ridge", "alps", "summit"]),
        (.tinRoof, ["tin roof", "roof", "hut", "shack"]),
        (.porch, ["porch", "deck", "backyard", "veranda"]),
        (.market, ["market", "bazaar", "souk"]),
        (.flight, ["airplane", "aeroplane", "plane", "flight", "airline"]),
    ]

    private static let skyWords: [(Sky, [String])] = [
        (.snowstorm, ["snowstorm", "snow storm", "blizzard", "whiteout"]),
        (.snow, ["snowy", "snowing", "snowfall", "snow", "winter"]),
        (.thunderstorm, ["thunderstorm", "thunder", "lightning", "stormy", "storm"]),
        (.downpour, ["downpour", "pouring", "heavy rain", "torrential", "monsoon"]),
        (.drizzle, ["drizzle", "drizzly", "light rain", "soft rain", "sprinkle"]),
        (.rain, ["rainy", "raining", "rain", "wet"]),
        (.fog, ["foggy", "fog", "misty", "mist", "haze"]),
        (.wind, ["windy", "wind", "gale", "gusty", "breezy"]),
        (.clear, ["clear", "sunny", "starry", "stars", "calm"]),
    ]

    private static let timeWords: [(TimeOfDay, [String])] = [
        (.dawn, ["dawn", "sunrise", "daybreak", "early morning"]),
        (.day, ["afternoon", "morning", "daytime", "midday", "noon", " day "]),
        (.dusk, ["dusk", "sunset", "evening", "twilight"]),
        (.night, ["midnight", "night", "nighttime", "late"]),
    ]
}
