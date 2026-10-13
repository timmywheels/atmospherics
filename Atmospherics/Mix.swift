import Foundation

/// How loud each sound plays. Every recording is mastered to the same loudness (`reference`) and
/// the synthesized sounds are calibrated to it, so a level means the same thing for every sound:
/// 1 is that sound at its fullest natural presence. `presenceDB` sets that presence, so a rustle
/// of leaves or a distant foghorn sits well under a downpour, the way it does outside.
enum Mix {
    /// LUFS of any sound at gain 1.
    static let reference = -20.0
    /// Where a scene settles (LUFS): calm, with room for a storm to be bigger than a still night.
    static let target = -24.0
    /// However much is stacked up, never louder than this (LUFS).
    static let ceiling = -18.0

    /// Roughly how loud sounds are together (LUFS), as independent sources.
    static func loudness(_ levels: [(SoundKind, Double)]) -> Double {
        let power = levels.reduce(0) { $0 + pow($1.1 * $1.0.presence, 2) }
        return power > 0 ? reference + 10 * log10(power) : -70
    }

    /// How loud one sound is at a level (LUFS).
    static func loudness(_ kind: SoundKind, _ level: Double) -> Double { loudness([(kind, level)]) }

    /// The engine gains for a field: each level at its sound's presence, all turned down
    /// together if the total would pass the ceiling.
    static func gains(_ levels: [SoundKind: Double]) -> [SoundKind: Double] {
        let total = loudness(levels.map { ($0.key, $0.value) })
        let trim = total > ceiling ? pow(10, (ceiling - total) / 20) : 1
        return levels.mapValues { $0 * trim }.reduce(into: [:]) { $0[$1.key] = $1.value * $1.key.presence }
    }

    /// Brings a scene most of the way to the target, so traveling doesn't jump in volume,
    /// while a storm still ends up louder than a still night.
    static func balance(_ levels: [(SoundKind, Double)]) -> [(SoundKind, Double)] {
        let total = loudness(levels)
        guard total > -70 else { return levels }
        let shift = max(-6, min(6, 0.7 * (target - total)))
        let scale = pow(10, shift / 20)
        return levels.map { ($0.0, min(1, $0.1 * scale)) }
    }
}

extension SoundKind {
    /// How present a sound is at full level, in dB under the loudest beds (a downpour, surf).
    var presenceDB: Double {
        switch self {
        // Weather and water: the air of a scene.
        case .heavyRain, .brown: 0
        case .rain, .thunder, .waterfall, .cabin, .fan, .pink, .green: -1
        case .ocean, .rocks, .rainyStreet, .cityHum, .cityNight, .grey: -2
        case .tentRain, .tinRoof, .wind, .treeWind, .gusts: -3
        case .howl: -5
        case .breeze: -6
        case .cafe, .train, .fire, .white, .blue, .lapping: -4
        case .violet, .traffic, .bazaar: -5
        case .highway: -6
        case .lightRain: -6
        case .lake, .caveDrips: -7
        // Life, and the life of a place: in front of the air, but never on top of you.
        case .jungleBirds, .canopy: -2
        case .birds, .winterBirds: -3
        case .parrots, .frogs: -4
        case .crickets, .treeFrogs: -5
        case .cicadas, .peepers, .howlers, .loons, .gulls, .geese, .whales, .bells, .drone, .lightning, .palms, .tram, .motorbikes, .fountain: -6
        case .halyards, .templeBell: -7
        case .owls: -7
        case .wolves, .foghorn, .library, .planes: -8
        // A stream babbles on without pause and carries in the quiet, so it sits well back.
        case .stream: -8
        // A pulse is for the background: under the rain, not on top of it.
        case .betaPulse: -7
        case .leaves, .buoy: -9
        // Binaural beats sit well under the noise they ride on, but clear enough to hear the beat.
        case .betaBeats, .gammaBeats: -11
        case .typing, .chimes: -10
        case .clock: -12
        }
    }

    /// Gain at full level (at most 1).
    var presence: Double { pow(10, presenceDB / 20) }

    /// What a synthesized sound's generator is multiplied by to reach the reference loudness.
    /// Recordings are mastered to it already.
    var calibration: Double {
        // Each generator alone at gain 1, in LUFS (`render synth` in design/soundscapes/render.swift).
        let measured: Double
        switch self {
        case .white: measured = -9.3
        case .pink: measured = -10.6
        case .brown: measured = -11.9
        case .green: measured = -10.5
        case .grey: measured = -10.6
        case .blue: measured = -7.2
        case .violet: measured = -11.4
        case .drone: measured = -22.4
        case .betaBeats: measured = -12.7
        case .gammaBeats: measured = -12.6
        case .betaPulse: measured = -11.9   // at depth 0.3 (−12.8 at 0.5, before it was softened)
        default: return 1
        }
        return pow(10, (Mix.reference - measured) / 20)
    }
}
