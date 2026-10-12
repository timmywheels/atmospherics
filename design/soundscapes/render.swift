// Renders sounds offline with the app's own sound code, to measure them and to preview mixes.
// Build from the repo root:
//   swiftc -parse-as-library -O -o /tmp/render Atmospherics/Sound.swift Atmospherics/Mix.swift \
//     Atmospherics/Places.swift Atmospherics/Weather.swift Atmospherics/Ecology.swift Atmospherics/NoiseEngine.swift \
//     Atmospherics/SampleBank.swift Atmospherics/Generators.swift Shared/Color+OKLCH.swift design/soundscapes/render.swift
//   /tmp/render synth <dir>                            each synthesized sound alone at gain 1 (uncalibrated), as WAV
//   /tmp/render mix <sounds dir> <out.wav> <seconds> [--uncalibrated] kind=gain ...
//                                                      engine gains, mixed as the app mixes them
//   /tmp/render scene <sounds dir> <out.wav> <seconds> <place> <month> <hour> <°C> <weather code> <rain mm> <wind km/h> [minute]
//                                                      a place's scene, composed and mixed as the app does
import AVFoundation

@main
struct Render {
    static let rate = 44_100.0

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first {
        case "synth":
            for kind in SoundKind.allCases where !kind.isRecorded {
                let url = URL(fileURLWithPath: args[1]).appendingPathComponent("\(kind.rawValue).wav")
                try write(synth([(kind, 1)], seconds: 30, calibrated: false), to: url)
            }
        case "mix":
            let gains: [(SoundKind, Double)] = args.dropFirst(4).compactMap {
                let p = $0.split(separator: "=")
                guard p.count == 2, let k = SoundKind(rawValue: String(p[0])), let g = Double(p[1]) else { return nil }
                return (k, g)
            }
            try write(mixdown(gains, from: URL(fileURLWithPath: args[1]), seconds: Double(args[3])!,
                              calibrated: !args.contains("--uncalibrated")), to: URL(fileURLWithPath: args[2]))
        case "scene":
            guard let place = Place.all.first(where: { $0.name == args[4] }) else { print("no place \(args[4])"); return }
            let n = args[5...10].map { Double($0)! }
            let c = Conditions(place: place.name, temperatureC: n[2], precipitationMM: n[4], windKMH: n[5],
                               pressureHPA: 1013, code: Int(n[3]), isDay: (7...18).contains(Int(n[1])),
                               latitude: place.latitude, utcOffset: 0, sunrise: 6 * 60 + 30, sunset: 18 * 60 + 30)
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .gmt
            let minute = args.count > 11 ? Int(args[11])! : 20
            let now = cal.date(from: DateComponents(year: 2026, month: Int(n[0]), day: 15, hour: Int(n[1]), minute: minute))!
            let levels = Soundscape.compose(c, place: place, now: now, playableOnly: false)
            let gains = Mix.gains(Dictionary(levels, uniquingKeysWith: max))
            print(levels.map { "\($0.0.rawValue) \(String(format: "%.2f", $0.1)) (\(Int(Mix.loudness($0.0, $0.1).rounded())) LUFS)" }
                .joined(separator: ", "))
            try write(mixdown(gains.map { ($0.key, $0.value) }, from: URL(fileURLWithPath: args[1]),
                              seconds: Double(args[3])!, calibrated: true), to: URL(fileURLWithPath: args[2]))
        default:
            print("usage: render synth <dir> | render mix … | render scene …  (see the top of render.swift)")
        }
    }

    /// Recordings looped from a random point, plus the synthesized sounds, at engine gains.
    static func mixdown(_ gains: [(SoundKind, Double)], from dir: URL, seconds: Double, calibrated: Bool) throws -> [[Float]] {
        var out = synth(gains.filter { !$0.0.isRecorded }, seconds: seconds, calibrated: calibrated)
        for (kind, gain) in gains where kind.isRecorded && gain > 0 {
            let loop = try decode(dir.appendingPathComponent("\(kind.rawValue).m4a"))
            // Events (a plane passing) play once from the start; everything else loops from a random point.
            let start = kind.isEvent ? 0 : Int(Double.random(in: 0..<0.8) * Double(loop[0].count))
            for c in 0..<2 {
                for i in 0..<out[c].count where !kind.isEvent || i < loop[c].count {
                    out[c][i] += Float(gain) * loop[c][(start + i) % loop[c].count]
                }
            }
        }
        return out
    }

    /// The synthesized sounds, as NoiseEngine makes them: a voice per channel, soft-clipped together.
    static func synth(_ gains: [(SoundKind, Double)], seconds: Double, calibrated: Bool) -> [[Float]] {
        let n = Int(seconds * rate)
        var out = [[Float]](repeating: [Float](repeating: 0, count: n), count: 2)
        let voices = gains.enumerated().map { i, entry in
            (Voice(entry.0, sampleRate: Float(rate), seed: UInt32(101 + i * 7)),
             Voice(entry.0, sampleRate: Float(rate), seed: UInt32(9001 + i * 13)),
             Float(entry.1 * (calibrated ? entry.0.calibration : 1)))
        }
        guard !voices.isEmpty else { return out }
        for i in 0..<n {
            var l: Float = 0, r: Float = 0
            for (left, right, g) in voices {
                l += left.next() * g
                r += right.next() * g
            }
            out[0][i] = tanhf(l)
            out[1][i] = tanhf(r)
        }
        return out
    }

    static func decode(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let n = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        return (0..<2).map { c in Array(UnsafeBufferPointer(start: buffer.floatChannelData![min(c, channels - 1)], count: n)) }
    }

    static func write(_ channels: [[Float]], to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let n = channels[0].count
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buffer.frameLength = AVAudioFrameCount(n)
        for c in 0..<2 { channels[c].withUnsafeBufferPointer { buffer.floatChannelData![c].update(from: $0.baseAddress!, count: n) } }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
