import Foundation

/// A synthesized sound with its own state. Called once per sample on the audio thread,
/// with the voice's white-noise sample and its helpers (random numbers, pink, brown).
protocol SoundGenerator: AnyObject {
    func next(_ v: Voice, _ w: Float) -> Float
}

func makeGenerator(for kind: SoundKind, sampleRate sr: Float, seed: UInt32) -> SoundGenerator? {
    // A per-channel number in 0…1, so left and right crickets, frogs and chimes differ.
    let variation = Float(seed % 997) / 997
    switch kind {
    case .grey: return Grey()
    case .blue: return Blue()
    case .violet: return Violet()
    case .crickets: return Crickets(sr: sr, variation: variation)
    case .cicadas: return Cicadas(sr: sr, variation: variation)
    case .frogs: return Frogs(sr: sr, variation: variation)
    case .stream: return Stream(sr: sr)
    case .cityHum: return CityHum(sr: sr)
    case .train: return Train(sr: sr, variation: variation)
    case .fan: return Fan(sr: sr)
    case .chimes: return Chimes(sr: sr)
    case .drone: return Drone(sr: sr, variation: variation)
    default: return nil
    }
}

// MARK: Building blocks

/// Chamberlin state-variable filter.
struct SVF {
    var low: Float = 0, band: Float = 0

    /// `f` is 2·sin(π·cutoff/sampleRate); smaller `q` rings more.
    mutating func bandpass(_ x: Float, f: Float, q: Float) -> Float {
        let high = x - low - q * band
        band += f * high
        low += f * band
        return band
    }

    static func coefficient(_ hz: Float, _ sr: Float) -> Float { 2 * sinf(.pi * min(hz, sr / 6) / sr) }
}

@inline(__always) private func wrap(_ phase: inout Float) {
    if phase > 2 * .pi { phase -= 2 * .pi }
}

// MARK: Noises

/// Shaped to sound equally loud at every pitch: weight in the lows, a little air on top.
final class Grey: SoundGenerator {
    func next(_ v: Voice, _ w: Float) -> Float {
        v.brown(w) * 0.45 + v.pink(w) * 0.55 + w * 0.05
    }
}

/// Rises 3 dB per octave: pink noise, differentiated.
final class Blue: SoundGenerator {
    private var previous: Float = 0
    func next(_ v: Voice, _ w: Float) -> Float {
        let p = v.pink(w)
        let out = p - previous
        previous = p
        return out * 1.6
    }
}

/// Rises 6 dB per octave: white noise, differentiated. Bright hiss.
final class Violet: SoundGenerator {
    private var previous: Float = 0
    func next(_ v: Voice, _ w: Float) -> Float {
        let out = w - previous
        previous = w
        return out * 0.16
    }
}

// MARK: Nature

/// Trills of three to five short pulses near 4.5 kHz, every half second or so.
final class Crickets: SoundGenerator {
    private let sr: Float, pitch: Float
    private var countdown = 0, pulsesLeft = 0, position = 0
    private let pulseLength: Int, gap: Int
    private var phase: Float = 0

    init(sr: Float, variation: Float) {
        self.sr = sr
        pitch = 4100 + 700 * variation
        pulseLength = Int(0.012 * sr)
        gap = Int(0.018 * sr)
        countdown = Int(sr * (0.2 + variation))
    }

    func next(_ v: Voice, _ w: Float) -> Float {
        if pulsesLeft == 0 {
            countdown -= 1
            if countdown <= 0 { pulsesLeft = 3 + Int(v.random01() * 3); position = 0 }
            return 0
        }
        position += 1
        if position >= pulseLength {
            pulsesLeft -= 1
            if pulsesLeft == 0 { countdown = Int(sr * (0.35 + 0.5 * v.random01())) } else { position = -gap }
            return 0
        }
        guard position >= 0 else { return 0 }
        let env = sinf(.pi * Float(position) / Float(pulseLength))
        phase += 2 * .pi * pitch / sr
        wrap(&phase)
        return (sinf(phase) * 0.8 + sinf(phase * 2) * 0.2) * env * 0.14
    }
}

/// A buzzing drone near 5.5 kHz, pulsing fast, swelling and fading over ten seconds or so.
final class Cicadas: SoundGenerator {
    private let sr: Float, f: Float, rate: Float
    private var svf = SVF()
    private var buzz: Float = 0, swell: Float

    init(sr: Float, variation: Float) {
        self.sr = sr
        f = SVF.coefficient(5200 + 800 * variation, sr)
        rate = 170 + 40 * variation
        swell = variation
    }

    func next(_ v: Voice, _ w: Float) -> Float {
        let band = svf.bandpass(w, f: f, q: 0.5)
        buzz += rate / sr
        if buzz >= 1 { buzz -= 1 }
        let pulse = powf(0.5 + 0.5 * sinf(2 * .pi * buzz), 2)
        swell += 1 / (sr * 11)
        if swell >= 1 { swell -= 1 }
        let level = 0.3 + 0.7 * powf(0.5 - 0.5 * cosf(2 * .pi * swell), 1.5)
        return band * pulse * level * 0.55
    }
}

/// Low, buzzy croaks in twos and threes every few seconds.
final class Frogs: SoundGenerator {
    private let sr: Float, pitch: Float
    private var countdown = 0, pulsesLeft = 0, position = 0
    private let pulseLength: Int, gap: Int
    private var phase: Float = 0, smooth: Float = 0

    init(sr: Float, variation: Float) {
        self.sr = sr
        pitch = 190 + 140 * variation
        pulseLength = Int(0.055 * sr)
        gap = Int(0.04 * sr)
        countdown = Int(sr * (0.5 + 2 * variation))
    }

    func next(_ v: Voice, _ w: Float) -> Float {
        if pulsesLeft == 0 {
            countdown -= 1
            if countdown <= 0 { pulsesLeft = 2 + Int(v.random01() * 2); position = 0 }
            return 0
        }
        position += 1
        if position >= pulseLength {
            pulsesLeft -= 1
            if pulsesLeft == 0 { countdown = Int(sr * (0.9 + 2.5 * v.random01())) } else { position = -gap }
            return 0
        }
        guard position >= 0 else { return 0 }
        let t = Float(position) / Float(pulseLength)
        let env = sqrtf(sinf(.pi * t))
        phase += 2 * .pi * pitch * (1 - 0.12 * t) / sr
        wrap(&phase)
        // A squared-off tone, softened, gives the throaty buzz.
        let buzzy = tanhf(4 * sinf(phase))
        smooth += 0.25 * (buzzy - smooth)
        return smooth * env * 0.2
    }
}

/// Babbling water: a band-passed wash with small rising "bloop" bubbles.
final class Stream: SoundGenerator {
    private let sr: Float, f: Float
    private var svf = SVF()
    private var freqs = [Float](repeating: 0, count: 4)
    private var amps = [Float](repeating: 0, count: 4)
    private var phases = [Float](repeating: 0, count: 4)
    private var flow: Float = 0.8

    init(sr: Float) {
        self.sr = sr
        f = SVF.coefficient(1400, sr)
    }

    func next(_ v: Voice, _ w: Float) -> Float {
        flow += (0.7 + 0.3 * v.random01() - flow) * 0.00005
        let wash = svf.bandpass(w, f: f, q: 1.0) * 0.4 * flow

        if v.random01() < 45 / sr {
            let i = amps.indices.min { amps[$0] < amps[$1] }!
            let r = v.random01()
            freqs[i] = 350 + 1300 * r * r
            amps[i] = 0.3 + 0.7 * v.random01()
            phases[i] = 0
        }
        var bubbles: Float = 0
        for i in 0..<4 where amps[i] > 0.001 {
            freqs[i] *= 1.00012   // bubbles rise in pitch as they collapse
            phases[i] += 2 * .pi * freqs[i] / sr
            wrap(&phases[i])
            bubbles += sinf(phases[i]) * amps[i]
            amps[i] *= 0.9965
        }
        return wash + bubbles * 0.11
    }
}

// MARK: City & home

/// A city at night: a low traffic rumble, faint hiss, and a car passing every so often.
final class CityHum: SoundGenerator {
    private let sr: Float
    private var lp: Float = 0, svf = SVF()
    private var countdown: Int, position = 0, length = 0
    private var peak: Float = 0

    init(sr: Float) {
        self.sr = sr
        countdown = Int(sr * 2)
    }

    func next(_ v: Voice, _ w: Float) -> Float {
        lp += 0.02 * (v.brown(w) - lp)
        var out = lp * 1.2 + v.pink(w) * 0.06

        countdown -= 1
        if countdown <= 0 {
            length = Int(sr * (3 + 3 * v.random01()))
            countdown = length + Int(sr * (4 + 10 * v.random01()))
            position = 0
            peak = 0.4 + 0.6 * v.random01()
        }
        if position < length {
            position += 1
            let t = Float(position) / Float(length)
            let env = powf(sinf(.pi * t), 2) * peak
            let cutoff = 300 + 900 * sinf(.pi * t)   // rises as it nears, falls as it leaves
            out += svf.bandpass(w, f: SVF.coefficient(cutoff, sr), q: 0.8) * env * 0.5
        }
        return out
    }
}

/// Inside a train: a swaying rumble and the double clack of wheels over rail joints.
final class Train: SoundGenerator {
    private let sr: Float, interval: Int, secondClack: Int
    private var lp: Float = 0, noise: Float = 0, sway: Float = 0
    private var counter = 0
    private var clack: Float = 0, resonance: Float = 0

    init(sr: Float, variation: Float) {
        self.sr = sr
        interval = Int(sr * (1.1 + 0.1 * variation))
        secondClack = Int(sr * 0.17)
        counter = Int(Float(interval) * variation)
    }

    func next(_ v: Voice, _ w: Float) -> Float {
        lp += 0.015 * (v.brown(w) - lp)
        sway += 1 / (sr * 6)
        if sway >= 1 { sway -= 1 }
        let rumble = lp * 1.4 * (0.85 + 0.15 * sinf(2 * .pi * sway))

        counter += 1
        if counter >= interval { counter = 0 }
        if counter == 0 || counter == secondClack {
            clack = 0.8 + 0.2 * v.random01()
            resonance = 0
        }
        noise += 0.1 * (w - noise)
        var hit: Float = 0
        if clack > 0.001 {
            resonance += 2 * .pi * 170 / sr
            wrap(&resonance)
            hit = (sinf(resonance) * 0.6 + noise * 0.4) * clack
            clack *= 0.9975
        }
        return rumble + hit * 0.35
    }
}

/// A box fan: soft broadband air, a faint blade flutter, and a little motor hum.
final class Fan: SoundGenerator {
    private let sr: Float
    private var lp: Float = 0, blade: Float = 0, hum: Float = 0

    init(sr: Float) { self.sr = sr }

    func next(_ v: Voice, _ w: Float) -> Float {
        lp += 0.15 * (v.pink(w) - lp)
        blade += 14 / sr
        if blade >= 1 { blade -= 1 }
        hum += 2 * .pi * 120 / sr
        wrap(&hum)
        return lp * 1.6 * (0.9 + 0.1 * sinf(2 * .pi * blade)) + sinf(hum) * 0.015
    }
}

// MARK: Calm

/// Wind chimes: pentatonic strikes every few seconds, each a bell-like set of partials.
final class Chimes: SoundGenerator {
    private static let notes: [Float] = [523.25, 587.33, 659.25, 783.99, 880, 1046.5]
    private static let ratios: [Float] = [1, 2.76, 5.4]
    private static let partialAmps: [Float] = [1, 0.5, 0.25]
    private let sr: Float
    private let decays: [Float]
    private var freqs = [Float](repeating: 0, count: 12)
    private var amps = [Float](repeating: 0, count: 12)
    private var phases = [Float](repeating: 0, count: 12)
    private var countdown: Int, slot = 0

    init(sr: Float) {
        self.sr = sr
        // Per-sample decay for ~3 s, ~1 s and ~0.4 s.
        decays = [3, 1, 0.4].map { 1 - 1 / ($0 * sr) }
        countdown = Int(sr)
    }

    func next(_ v: Voice, _ w: Float) -> Float {
        countdown -= 1
        if countdown <= 0 {
            countdown = Int(sr * (1.2 + 3.3 * v.random01()))
            let note = Self.notes[Int(v.random01() * Float(Self.notes.count)) % Self.notes.count]
            let strength = 0.4 + 0.6 * v.random01()
            for p in 0..<3 {
                let i = slot * 3 + p
                freqs[i] = note * Self.ratios[p]
                amps[i] = strength * Self.partialAmps[p]
                phases[i] = 0
            }
            slot = (slot + 1) % 4
        }
        var out: Float = 0
        for i in 0..<12 where amps[i] > 0.0005 {
            phases[i] += 2 * .pi * freqs[i] / sr
            wrap(&phases[i])
            out += sinf(phases[i]) * amps[i]
            amps[i] *= decays[i % 3]
        }
        return out * 0.13
    }
}

/// A warm, slowly breathing pad on G: root, fifth and octave, each doubled and detuned.
final class Drone: SoundGenerator {
    private let sr: Float
    private let freqs: [Float]
    private var phases = [Float](repeating: 0, count: 6)
    private var lfo: Float
    private var breath: Float = 0

    init(sr: Float, variation: Float) {
        self.sr = sr
        let base: [Float] = [98, 146.83, 196]
        freqs = base + base.map { $0 * 1.003 }
        lfo = variation
    }

    func next(_ v: Voice, _ w: Float) -> Float {
        lfo += 1 / (sr * 13)
        if lfo >= 1 { lfo -= 1 }
        var out: Float = 0
        for i in 0..<6 {
            phases[i] += 2 * .pi * freqs[i] / sr
            wrap(&phases[i])
            let swell = 0.6 + 0.4 * sinf(2 * .pi * lfo + Float(i))
            out += sinf(phases[i]) * swell
        }
        breath += 0.02 * (w - breath)
        return out * 0.055 + breath * 0.05
    }
}
