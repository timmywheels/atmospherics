import SwiftUI

/// Every sound Atmospherics can play. All are synthesized live in `NoiseEngine`.
enum SoundKind: String, CaseIterable, Identifiable, Codable {
    case brown, pink, white, green, rain, ocean, wind, thunder, fire, birds
    case grey, blue, violet, crickets, cicadas, frogs, stream, cityHum, train, fan, chimes, drone, lightning
    // Recorded (public-domain field recordings in Sounds/)
    case howlers, jungleBirds, parrots, canopy, treeFrogs
    case owls, loons, wolves, leaves
    case waterfall, caveDrips, tentRain, tinRoof, whales, lake
    case cafe, library, cabin, bells, typing, clock, rainyStreet, lightRain, heavyRain
    case winterBirds, gulls, foghorn, peepers, geese
    case traffic, highway, planes
    case lapping, palms, rocks, buoy, halyards
    case tram, motorbikes, fountain, templeBell, bazaar
    // Synthesized focus tones
    case betaBeats, gammaBeats, betaPulse

    /// Recorded sounds play from `Sounds/<rawValue>.m4a` instead of being synthesized.
    var isRecorded: Bool {
        switch self {
        case .howlers, .jungleBirds, .parrots, .canopy, .treeFrogs, .owls, .loons, .wolves, .leaves,
             .waterfall, .caveDrips, .tentRain, .tinRoof, .whales, .lake,
             .cafe, .library, .cabin, .bells, .typing, .clock, .cityHum, .rainyStreet,
             .rain, .lightRain, .heavyRain, .thunder, .fire, .crickets, .ocean, .birds, .stream, .train, .wind, .cicadas, .frogs,
             .winterBirds, .gulls, .foghorn, .peepers, .geese, .traffic, .highway, .planes,
             .lapping, .palms, .rocks, .buoy, .halyards, .tram, .motorbikes, .fountain, .templeBell, .bazaar: true
        default: false
        }
    }

    /// One-off events (a plane passing over, geese flying by, a tram, a temple bell) play through once from the start
    /// when they come on, instead of looping.
    var isEvent: Bool { [.planes, .geese, .tram, .templeBell].contains(self) }

    /// This sound if the app has it, otherwise the closest synthesized one (or nothing).
    var playable: SoundKind? {
        if !isRecorded || SoundKind.available.contains(self) { return self }
        switch self {
        case .jungleBirds, .parrots: return .birds
        case .treeFrogs, .peepers: return .frogs
        case .canopy: return .cicadas
        case .tentRain, .tinRoof, .lightRain, .heavyRain: return .rain
        case .waterfall, .caveDrips: return .stream
        case .lake, .whales, .lapping, .rocks: return .ocean
        case .leaves: return .wind
        case .palms: return .leaves
        case .cafe, .rainyStreet, .traffic, .highway, .bazaar: return .cityHum
        case .motorbikes: return .traffic
        case .fountain: return .stream
        case .templeBell: return .bells
        case .bells: return .chimes
        case .cabin: return .fan
        // Better silent than wrong: no stand-in for these (a spring chorus is no winter bird).
        default: return nil   // howlers, owls, loons, wolves, library, typing, clock, winter birds, gulls, foghorn, geese, planes, buoy, rigging, tram
        }
    }

    /// Recorded sounds whose file is actually in the app. Ones without a file are hidden.
    static let available: [SoundKind] = allCases.filter {
        !$0.isRecorded || Bundle.main.url(forResource: $0.rawValue, withExtension: "m4a") != nil
    }

    var id: String { rawValue }

    enum Category: String, CaseIterable {
        case noise = "Noise", water = "Water & weather", nature = "Nature", jungle = "Jungle", night = "Night & forest",
             city = "Places & home", calm = "Calm", tones = "Focus tones"
    }

    var category: Category {
        switch self {
        case .brown, .pink, .white, .green, .grey, .blue, .violet: .noise
        case .rain, .lightRain, .heavyRain, .ocean, .stream, .wind, .thunder, .lightning: .water
        case .birds, .crickets, .cicadas, .frogs, .fire: .nature
        case .cityHum, .train, .fan: .city
        case .chimes, .drone, .bells: .calm
        case .howlers, .jungleBirds, .parrots, .canopy, .treeFrogs: .jungle
        case .owls, .loons, .wolves, .leaves: .night
        case .waterfall, .caveDrips, .tentRain, .tinRoof, .whales, .lake: .water
        case .cafe, .library, .cabin, .typing, .clock, .rainyStreet: .city
        case .winterBirds, .geese, .peepers: .nature
        case .gulls, .foghorn: .water
        case .traffic, .highway, .planes: .city
        case .lapping, .rocks, .buoy, .halyards: .water
        case .palms: .nature
        case .tram, .motorbikes, .bazaar: .city
        case .fountain: .water
        case .templeBell: .calm
        case .betaBeats, .gammaBeats, .betaPulse: .tones
        }
    }

    var name: String {
        switch self {
        case .brown, .pink, .white, .green, .grey, .blue, .violet: "\(short) noise"
        case .cityHum: "City street"
        case .jungleBirds: "Jungle birds"
        case .treeFrogs: "Tree frogs"
        case .caveDrips: "Cave drips"
        case .tentRain: "Rain on a tent"
        case .tinRoof: "Rain on a tin roof"
        case .cabin: "Airplane cabin"
        case .bells: "Church bells"
        case .rainyStreet: "Rainy street"
        case .lightRain: "Light rain"
        case .heavyRain: "Downpour"
        case .winterBirds: "Winter birds"
        case .peepers: "Spring peepers"
        case .lapping: "Lapping water"
        case .palms: "Palm fronds"
        case .rocks: "Surf on rocks"
        case .buoy: "Bell buoy"
        case .halyards: "Sailboat rigging"
        case .templeBell: "Temple bell"
        case .betaBeats: "Beta beats, 16 Hz"
        case .gammaBeats: "Gamma beats, 40 Hz"
        case .betaPulse: "Beta pulse, 16 Hz"
        default: short
        }
    }

    var short: String {
        switch self {
        case .cityHum: "City"
        case .howlers: "Howlers"
        case .jungleBirds: "Jungle birds"
        case .treeFrogs: "Tree frogs"
        case .caveDrips: "Cave"
        case .tentRain: "Tent"
        case .tinRoof: "Tin roof"
        case .cafe: "Café"
        case .rainyStreet: "Wet street"
        case .lightRain: "Drizzle"
        case .heavyRain: "Downpour"
        case .winterBirds: "Winter birds"
        case .lapping: "Lapping"
        case .halyards: "Rigging"
        case .templeBell: "Temple bell"
        case .betaBeats: "Beta beats"
        case .gammaBeats: "Gamma beats"
        case .betaPulse: "Beta pulse"
        default: rawValue.capitalized
        }
    }

    /// OKLCH hue from the design.
    var hue: Double {
        switch self {
        case .brown: 55
        case .pink: 10
        case .white: 260
        case .green: 140
        case .rain: 235
        case .ocean: 205
        case .wind: 175
        case .thunder: 290
        case .fire: 35
        case .birds: 100
        case .grey: 250
        case .blue: 265
        case .violet: 300
        case .crickets: 120
        case .cicadas: 85
        case .frogs: 150
        case .stream: 195
        case .cityHum: 325
        case .train: 245
        case .fan: 220
        case .chimes: 345
        case .drone: 275
        case .lightning: 95
        case .howlers: 70
        case .jungleBirds: 115
        case .parrots: 130
        case .canopy: 145
        case .treeFrogs: 160
        case .owls: 40
        case .loons: 215
        case .wolves: 280
        case .leaves: 105
        case .waterfall: 200
        case .caveDrips: 255
        case .tentRain: 230
        case .winterBirds: 90
        case .gulls: 225
        case .foghorn: 250
        case .peepers: 135
        case .geese: 60
        case .traffic: 20
        case .highway: 335
        case .planes: 185
        case .lapping: 182
        case .palms: 122
        case .rocks: 212
        case .buoy: 28
        case .halyards: 268
        case .tram: 92
        case .motorbikes: 0
        case .fountain: 190
        case .templeBell: 75
        case .bazaar: 32
        case .betaBeats: 312
        case .gammaBeats: 355
        case .betaPulse: 15
        case .tinRoof: 240
        case .whales: 250
        case .lake: 210
        case .cafe: 45
        case .library: 60
        case .cabin: 225
        case .bells: 80
        case .typing: 300
        case .clock: 50
        case .rainyStreet: 235
        case .lightRain: 215
        case .heavyRain: 250
        }
    }

    /// How saturated the color is, relative to the design's default. Grey and the
    /// mechanical sounds stay muted; blue leans vivid so it isn't mistaken for white.
    private var chroma: Double {
        switch self {
        case .grey: 0.1
        case .fan, .train: 0.4
        case .blue: 1.3
        default: 1
        }
    }

    /// The orb color on the mixer field.
    var orb: Color { .oklch(0.8, 0.12 * chroma, hue) }
    /// The orb's glow.
    var glow: Color { .oklch(0.7, 0.16 * chroma, hue) }
    /// The soft halo on Now Playing.
    var halo: Color { .oklch(0.6, 0.14 * chroma, hue) }
}

/// Colors and type from the Field design.
enum Theme {
    static let background = Color(hex: 0x0c0e13)
    static let text = Color(hex: 0xeceef2)
    static let secondary = Color(hex: 0xb9bec8)
    static let muted = Color(hex: 0x9aa0ab)
    static let orbLabel = Color(hex: 0xc9ced8)
    static let hairline = Color.white.opacity(0.14)

    /// Stands in for Geist Light.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .light) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    /// Small labels and captions, in the same clean sans as everything else (a point larger than
    /// the monospace they replaced, which ran wider). Tracked out when in capitals.
    static func label(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size + 1, weight: weight)
    }
    /// The wordmark alone keeps the monospace: it's the brand, not a label.
    static func brand(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}
