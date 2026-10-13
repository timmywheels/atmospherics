import Foundation

/// How a sound comes and goes over time. Most sounds are always there, but a wolf that howls
/// without pause is a recording, not a wolf: the rest come now and then, one take at a time, from
/// somewhere around you, never twice the same in a row.
enum Rhythm: Equatable {
    /// Always there, looping without a seam: rain, wind, the sea, crickets, a café.
    case bed
    /// An animal calling now and then from somewhere around you, near or far, often more than once
    /// from the same spot before it goes quiet: an owl's run of hoots, a wolf answering a wolf.
    /// `gap` is the quiet between, in seconds; `again` is how likely it calls again soon.
    case calls(gap: ClosedRange<Double>, again: Double)
    /// Something made that sounds from one place at its own steady pace, `every` so many seconds
    /// from one start to the next: a foghorn, a church bell tolling, a temple bell.
    case signal(every: ClosedRange<Double>)
    /// Something going by now and then, with `gap` seconds of quiet between: a plane overhead, a
    /// tram, geese.
    case passes(gap: ClosedRange<Double>)
    /// Weather breaking in, near or far, `gap` seconds apart: thunder, lightning.
    case strikes(gap: ClosedRange<Double>)
}

extension SoundKind {
    /// How this sound comes and goes. Anything not listed is a bed.
    var rhythm: Rhythm {
        switch self {
        case .wolves: .calls(gap: 30...90, again: 0.3)
        case .owls: .calls(gap: 20...60, again: 0.45)
        case .loons: .calls(gap: 20...60, again: 0.35)
        case .howlers: .calls(gap: 25...80, again: 0.65)
        case .whales: .calls(gap: 20...70, again: 0.5)
        case .foghorn: .signal(every: 25...35)
        case .templeBell: .signal(every: 60...150)
        case .bells: .signal(every: 120...300)
        case .planes: .passes(gap: 90...240)
        case .tram: .passes(gap: 60...180)
        case .geese: .passes(gap: 120...360)
        case .thunder: .strikes(gap: 9...35)
        case .lightning: .strikes(gap: 14...48)
        default: .bed
        }
    }

    /// The recordings that make this sound: `rain.m4a`; for one that comes and goes, its takes
    /// (`wolves1.m4a`, `wolves2.m4a`…, cut from a longer recording by design/sounds/calls.swift),
    /// or its one recording if it has a single take (a plane going over).
    var recordings: [String] { recordings { Bundle.main.url(forResource: $0, withExtension: "m4a") != nil } }

    /// The same, from wherever `exists` looks.
    func recordings(_ exists: (String) -> Bool) -> [String] {
        guard rhythm != .bed else { return [rawValue] }
        var takes: [String] = []
        while exists("\(rawValue)\(takes.count + 1)") { takes.append("\(rawValue)\(takes.count + 1)") }
        return takes.isEmpty ? [rawValue] : takes
    }
}

/// Where a sound that comes and goes is up to: where its next take comes from, how near, and how
/// long until it does. `SampleBank` keeps one for each such sound while it plays.
struct Pacing {
    let rhythm: Rhythm
    /// Left to right, -1...1, for the take about to play.
    private(set) var pan: Float = 0
    /// How near the take is: a gain on top of the sound's own level.
    private(set) var gain: Float = 1
    /// Where a signal sounds from, all the while it plays: a foghorn doesn't move.
    private let home = Float.random(in: -0.4...0.4)
    /// Whether the animal calls again soon, from the same spot.
    private var soon = false

    init(_ rhythm: Rhythm) { self.rhythm = rhythm }

    /// The first take comes soon after the sound comes on, so you hear what you added.
    static let first: ClosedRange<Double> = 1...4

    /// Places the take about to play.
    mutating func next() {
        switch rhythm {
        case .bed: break
        case .calls:
            // Calling again: the same animal, where it was. Otherwise another, somewhere else.
            if !soon { pan = .random(in: -0.8...0.8); gain = .random(in: 0.55...1) }
        case .signal:
            // The wind carries it a little more or less.
            pan = home; gain = .random(in: 0.8...1)
        case .passes:
            pan = .random(in: -0.3...0.3); gain = .random(in: 0.75...1)
        case .strikes:
            pan = .random(in: -0.6...0.6); gain = .random(in: 0.7...1)
        }
    }

    /// The quiet, in seconds, after a take `length` seconds long, before the next one starts.
    mutating func pause(after length: Double) -> Double {
        switch rhythm {
        case .bed:
            return 0
        case .calls(let gap, let again):
            soon = .random(in: 0..<1) < again
            return soon ? .random(in: 2...7) : .random(in: gap)
        case .signal(let every):
            // Steady from one start to the next, the take itself included.
            return max(1, .random(in: every) - length)
        case .passes(let gap), .strikes(let gap):
            return .random(in: gap)
        }
    }
}
