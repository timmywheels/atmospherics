import Foundation

struct Preset: Identifiable {
    enum Tag: String, CaseIterable { case sleep = "Sleep", focus = "Focus", relax = "Relax" }

    /// How well research backs a focus mix, in plain words (see FocusScienceView).
    enum Evidence: String {
        case strong = "Strong evidence", some = "Some evidence", early = "Early evidence", mixed = "Mixed evidence"
    }

    let name: String
    let tag: Tag?          // nil for a mix you saved
    let length: String
    let description: String
    let mix: [(SoundKind, Double)]
    /// A saved mix keeps its exact field instead of being laid out from `mix`.
    var savedOrbs: [Orb]? = nil
    var savedID: UUID? = nil
    var evidence: Evidence? = nil

    var id: String { savedID?.uuidString ?? name }
    var isSaved: Bool { savedID != nil }

    static let all: [Preset] = [
        // Focus mixes built on what research supports (design/focus/RESEARCH.md).
        Preset(name: "Quiet Car", tag: .focus, length: "2 h", description: "Pink noise and a steady stream cover nearby voices",
               mix: [(.pink, 0.55), (.stream, 0.55)], evidence: .strong),
        Preset(name: "Steady Rain", tag: .focus, length: "2 h", description: "Rain that doesn't change, over a low hush",
               mix: [(.rain, 0.7), (.brown, 0.25)], evidence: .strong),
        Preset(name: "Restless Mind", tag: .focus, length: "1 h", description: "White and pink noise, for when your mind wanders",
               mix: [(.pink, 0.55), (.white, 0.3)], evidence: .some),
        Preset(name: "Beta Pulse", tag: .focus, length: "90 min", description: "Pink noise pulsing at 16 Hz, soft rain",
               mix: [(.betaPulse, 0.6), (.lightRain, 0.3)], evidence: .early),
        Preset(name: "Beta Beats", tag: .focus, length: "90 min", description: "16 Hz binaural beats in pink noise · headphones",
               mix: [(.pink, 0.6), (.betaBeats, 0.7)], evidence: .mixed),
        Preset(name: "Gamma Beats", tag: .focus, length: "1 h", description: "40 Hz binaural beats in brown noise · headphones",
               mix: [(.brown, 0.6), (.gammaBeats, 0.7)], evidence: .mixed),
        Preset(name: "Green Break", tag: .focus, length: "10 min", description: "Birdsong and a stream, between focus blocks",
               mix: [(.birds, 0.55), (.stream, 0.5), (.leaves, 0.2)], evidence: .some),
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
        Preset(name: "Temple Garden", tag: .relax, length: "45 min", description: "Stream, chimes, birds",
               mix: [(.stream, 0.65), (.chimes, 0.3), (.birds, 0.2)]),
        Preset(name: "Grey Room", tag: .focus, length: "2 h", description: "Grey noise, a warm drone",
               mix: [(.grey, 0.7), (.drone, 0.3)]),
        Preset(name: "Box Fan", tag: .sleep, length: "8 h", description: "Fan, brown noise",
               mix: [(.fan, 0.75), (.brown, 0.3)]),
        Preset(name: "Campsite", tag: .sleep, length: "8 h", description: "Rain on the tent, owls, a low fire",
               mix: [(.tentRain, 0.75), (.owls, 0.25), (.fire, 0.3)]),
        Preset(name: "Tin Roof Nap", tag: .sleep, length: "2 h", description: "Rain on a tin roof, tree frogs",
               mix: [(.tinRoof, 0.75), (.treeFrogs, 0.25), (.brown, 0.25)]),
        Preset(name: "Red-eye", tag: .sleep, length: "8 h", description: "Airplane cabin, brown noise",
               mix: [(.cabin, 0.75), (.brown, 0.3)]),
        Preset(name: "North Woods", tag: .sleep, length: "8 h", description: "Lake, loons, leaves, owls",
               mix: [(.lake, 0.6), (.loons, 0.35), (.leaves, 0.3), (.owls, 0.2)]),
        Preset(name: "Wolf Moon", tag: .relax, length: "1 h", description: "Distant wolves, wind, a fire",
               mix: [(.wind, 0.5), (.wolves, 0.3), (.fire, 0.4)]),
        // No ticking clock: sounds that keep changing are the ones that pull attention away.
        Preset(name: "Reading Room", tag: .focus, length: "2 h", description: "A library's hush, rain on the windows",
               mix: [(.library, 0.7), (.rain, 0.3)]),
        Preset(name: "Coffee Shop", tag: .focus, length: "90 min", description: "A lively café's murmur, for creative work",
               mix: [(.cafe, 0.75), (.rain, 0.25)], evidence: .some),
        Preset(name: "Late Draft", tag: .relax, length: "90 min", description: "Typing, a clock, pink noise",
               mix: [(.typing, 0.5), (.clock, 0.25), (.pink, 0.4)]),
        Preset(name: "Cave Retreat", tag: .relax, length: "1 h", description: "Cave drips, a warm drone",
               mix: [(.caveDrips, 0.7), (.drone, 0.3)]),
        Preset(name: "Whale Song", tag: .relax, length: "45 min", description: "Whales, ocean, a warm drone",
               mix: [(.whales, 0.55), (.ocean, 0.5), (.drone, 0.2)]),
        Preset(name: "Clear Head", tag: .focus, length: "1 h", description: "Blue noise, a little white",
               mix: [(.blue, 0.6), (.white, 0.2)]),
        Preset(name: "Bright Hiss", tag: .focus, length: "1 h", description: "Violet and pink noise",
               mix: [(.violet, 0.4), (.pink, 0.45)]),
        Preset(name: "Rainforest", tag: .relax, length: "1 h", description: "Canopy, howler monkeys, a waterfall",
               mix: [(.canopy, 0.7), (.howlers, 0.3), (.waterfall, 0.3)]),
    ]

    /// Places each sound at the distance from center that gives its volume,
    /// spread around the field so orbs don't overlap.
    var orbs: [Orb] {
        if let saved = savedOrbs { return saved.compactMap { o in o.kind.playable.map { Orb(id: $0.stableID, kind: $0, x: o.x, y: o.y) } } }
        return Self.layout(mix.compactMap { k, v in k.playable.map { ($0, v) } })
    }

    static func layout(_ mix: [(SoundKind, Double)]) -> [Orb] {
        mix.enumerated().map { j, entry in
            let (kind, volume) = entry
            let r = (1 - volume) * 0.5
            let angle = Double(j) * 2.4 + 0.6
            return Orb(id: kind.stableID, kind: kind, x: 0.5 + cos(angle) * r, y: 0.5 + sin(angle) * r)
        }
    }
}

/// Match outside follows the local weather; Escape plays a real place's; Atmosphere plays a
/// scene by name ("a log cabin in a snowstorm").
enum Mode: String, Codable, CaseIterable {
    case match, escape, atmosphere
}

/// What the header and subtitles say about the weather.
struct WeatherSummary {
    let place: String
    let temp: String
    let line: String
    let head: String
}

extension SoundKind {
    /// The same ID for a sound everywhere it's laid out, so its light keeps its animation
    /// when it moves between the carousel's pages and the live field.
    var stableID: UUID {
        let i = SoundKind.allCases.firstIndex(of: self) ?? 0
        return UUID(uuidString: String(format: "A7505000-0000-0000-0000-%012d", i))!
    }
}

/// A mix you saved: its exact field, and where it came from.
struct SavedMix: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var origin: String
    var created = Date()
    var orbs: [Orb]

    var preset: Preset {
        Preset(name: name, tag: nil, length: "Yours", description: origin,
               mix: orbs.sorted { $0.volume > $1.volume }.map { ($0.kind, $0.volume) },
               savedOrbs: orbs, savedID: id)
    }
}
