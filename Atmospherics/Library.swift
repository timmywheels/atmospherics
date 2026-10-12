import Foundation

struct Preset: Identifiable {
    enum Tag: String, CaseIterable { case sleep = "Sleep", focus = "Focus", relax = "Relax" }

    let name: String
    let tag: Tag
    let length: String
    let description: String
    let mix: [(SoundKind, Double)]

    var id: String { name }

    static let all: [Preset] = [
        Preset(name: "Attic Rain", tag: .sleep, length: "8 h", description: "Brown noise, rain, distant thunder",
               mix: [(.brown, 0.8), (.rain, 0.6), (.thunder, 0.2)]),
        Preset(name: "Deep Work", tag: .focus, length: "90 min", description: "Pink noise, light wind",
               mix: [(.pink, 0.7), (.wind, 0.3)]),
        Preset(name: "Low Tide", tag: .relax, length: "45 min", description: "Ocean, green noise",
               mix: [(.ocean, 0.8), (.green, 0.4)]),
        Preset(name: "Thursday’s Storm", tag: .sleep, length: "8 h", description: "Rain, wind, thunder, lightning",
               mix: [(.rain, 0.9), (.wind, 0.6), (.thunder, 0.4), (.lightning, 0.35), (.brown, 0.3)]),
        Preset(name: "Fog Bank", tag: .focus, length: "2 h", description: "White noise, ocean",
               mix: [(.white, 0.5), (.ocean, 0.5)]),
        Preset(name: "Ember", tag: .relax, length: "30 min", description: "Fire, brown noise, birds",
               mix: [(.fire, 0.7), (.brown, 0.4), (.birds, 0.15)]),
        Preset(name: "Night Train", tag: .sleep, length: "8 h", description: "Train, rain on the windows, brown noise",
               mix: [(.train, 0.7), (.rain, 0.35), (.brown, 0.4)]),
        Preset(name: "Summer Porch", tag: .relax, length: "1 h", description: "Crickets, frogs, a light breeze",
               mix: [(.crickets, 0.6), (.frogs, 0.35), (.wind, 0.2)]),
        Preset(name: "Temple Garden", tag: .focus, length: "45 min", description: "Stream, chimes, birds",
               mix: [(.stream, 0.65), (.chimes, 0.3), (.birds, 0.2)]),
        Preset(name: "Grey Room", tag: .focus, length: "2 h", description: "Grey noise, a warm drone",
               mix: [(.grey, 0.7), (.drone, 0.3)]),
        Preset(name: "Box Fan", tag: .sleep, length: "8 h", description: "Fan, brown noise",
               mix: [(.fan, 0.75), (.brown, 0.3)]),
    ]

    /// Places each sound at the distance from center that gives its volume,
    /// spread around the field so orbs don't overlap.
    var orbs: [Orb] { Self.layout(mix) }

    static func layout(_ mix: [(SoundKind, Double)]) -> [Orb] {
        mix.enumerated().map { j, entry in
            let (kind, volume) = entry
            let r = (1 - volume) * 0.5
            let angle = Double(j) * 2.4 + 0.6
            return Orb(kind: kind, x: 0.5 + cos(angle) * r, y: 0.5 + sin(angle) * r)
        }
    }
}

/// Match outside follows the local weather; Escape plays somewhere else's.
enum Mode: String, Codable, CaseIterable {
    case match, escape
}

/// What the header and subtitles say about the weather.
struct WeatherSummary {
    let place: String
    let temp: String
    let line: String
    let head: String
}
