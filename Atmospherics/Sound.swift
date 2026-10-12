import SwiftUI

/// Every sound Atmospherics can play. All are synthesized live in `NoiseEngine`.
enum SoundKind: String, CaseIterable, Identifiable, Codable {
    case brown, pink, white, green, rain, ocean, wind, thunder, fire, birds
    case grey, blue, violet, crickets, cicadas, frogs, stream, cityHum, train, fan, chimes, drone

    var id: String { rawValue }

    enum Category: String, CaseIterable {
        case noise = "Noise", water = "Water & weather", nature = "Nature", city = "City & home", calm = "Calm"
    }

    var category: Category {
        switch self {
        case .brown, .pink, .white, .green, .grey, .blue, .violet: .noise
        case .rain, .ocean, .stream, .wind, .thunder: .water
        case .birds, .crickets, .cicadas, .frogs, .fire: .nature
        case .cityHum, .train, .fan: .city
        case .chimes, .drone: .calm
        }
    }

    var name: String {
        switch self {
        case .brown, .pink, .white, .green, .grey, .blue, .violet: "\(short) noise"
        case .cityHum: "City hum"
        default: short
        }
    }

    var short: String {
        switch self {
        case .cityHum: "City"
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
    static let mono = Color(hex: 0x9aa0ab)
    static let orbLabel = Color(hex: 0xc9ced8)
    static let hairline = Color.white.opacity(0.14)

    /// Stands in for Geist Light.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .light) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    /// Stands in for Geist Mono.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
