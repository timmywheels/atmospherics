import AVFoundation

// Cuts the separate calls out of a recording, for the sounds that come and go (`SoundKind.rhythm`
// in the app): a wolf's howl, a run of hoots, a foghorn's blast, a bell tolling. Each take keeps a
// moment of quiet before the call and its tail after, fades in and out so it starts and ends in
// silence, and keeps the recording's level, so a call plays as loud as it did in the loop.
//
//   swift calls.swift find <recording.m4a> [low-high Hz] [rise dB]
//       Where the calls are, as "start end" in seconds. Listening only in the calls' own band
//       (an owl's hoots at 250-900 Hz) finds them under wind or surf that's louder overall.
//   swift calls.swift cut
//       Writes every take in `takes` below, from design/sounds/loops/<sound>.m4a to
//       Atmospherics/Sounds/<sound>1.m4a, <sound>2.m4a… Run from the repository's root.

/// Each sound's takes, in seconds into its recording, found with `find` and checked against a
/// spectrogram. `highpass` drops a rumble under the calls that would otherwise swell in with each one.
let takes: [(sound: String, highpass: Double?, spans: [(Double, Double)])] = [
    ("wolves", nil, [(0, 9.3), (9.1, 18.2), (26.5, 36.6), (37.9, 48)]),
    // Hoots at 250-900 Hz over a wind rumble.
    ("owls", 150, [(0, 4.6), (8.4, 12.4), (18.6, 23), (28.8, 33.4), (40, 44.4), (45.8, 51.3), (51.2, 58.6)]),
    // Single wails first, then the chorus cut at its quietest moments.
    ("loons", nil, [(0, 4.8), (10.6, 13.3), (13.2, 15.4), (15.2, 17.8), (17.6, 20.2), (20.1, 28.6),
                    (29.6, 32.2), (32.2, 42.1), (42, 51.7), (51.6, 57.4)]),
    ("howlers", nil, [(3.95, 10.05), (11.1, 16.75), (17.1, 22.35), (24.6, 30.15), (32.95, 37.65), (44.15, 49.45), (50, 56.75)]),
    // Blows at 150-900 Hz over a boat's rumble.
    ("whales", 100, [(1, 4.1), (6.15, 9.25), (13.45, 16.5), (22.75, 24.9), (28.1, 31.05), (39.85, 43.55), (48.2, 51.05)]),
    // Each blast with its echo off the water, over the sea's rumble.
    ("foghorn", 140, [(16.4, 23), (35.6, 40.4), (55.5, 60.3), (75.5, 80.3)]),
    // Seven tolls; the 38 s before them are only wind and traffic.
    ("bells", 200, [(38.4, 57.5)]),
]

// MARK: Reading and filtering

func read(_ path: String) throws -> AVAudioPCMBuffer {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return buffer
}

/// A second-order Butterworth filter (the RBJ cookbook's), run in place over every channel.
func filter(_ buffer: AVAudioPCMBuffer, highpass: Bool, at hz: Double) {
    let w = 2 * Double.pi * hz / buffer.format.sampleRate
    let alpha = sin(w) / (2 * 0.7071), c = cos(w)
    let b0 = highpass ? (1 + c) / 2 : (1 - c) / 2
    let b1 = highpass ? -(1 + c) : 1 - c
    let a0 = 1 + alpha, a1 = -2 * c, a2 = 1 - alpha
    for ch in 0..<Int(buffer.format.channelCount) {
        let x = buffer.floatChannelData![ch]
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<Int(buffer.frameLength) {
            let x0 = Double(x[i])
            let y0 = (b0 * x0 + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2) / a0
            x2 = x1; x1 = x0; y2 = y1; y1 = y0
            x[i] = Float(y0)
        }
    }
}

// MARK: Finding calls

func find(_ path: String, band: (Double, Double)?, rise: Double) throws {
    let buffer = try read(path)
    if let band {
        for _ in 0..<2 { filter(buffer, highpass: true, at: band.0); filter(buffer, highpass: false, at: band.1) }
    }
    let n = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
    let step = 0.05, window = Int(buffer.format.sampleRate * step)
    var levels: [Double] = []
    var i = 0
    while i + window <= n {
        var sum = 0.0
        for c in 0..<channels {
            let data = buffer.floatChannelData![c]
            for j in i..<(i + window) { sum += Double(data[j] * data[j]) }
        }
        levels.append(10 * log10(max(1e-12, sum / Double(window * channels))))
        i += window
    }
    // Smoothed over a quarter second, so a call's own flutter doesn't split it.
    let smooth = levels.indices.map { k -> Double in
        let lo = max(0, k - 2), hi = min(levels.count - 1, k + 2)
        return levels[lo...hi].reduce(0, +) / Double(hi - lo + 1)
    }
    let sorted = smooth.sorted()
    let floor = sorted[sorted.count / 5]   // the quiet between calls
    let threshold = floor + rise

    var regions: [(Int, Int)] = []
    var start: Int?
    for (k, v) in smooth.enumerated() {
        if v > threshold { if start == nil { start = k } } else if let s = start { regions.append((s, k)); start = nil }
    }
    if let s = start { regions.append((s, smooth.count)) }
    // Calls less than 0.8 s apart are one call.
    var merged: [(Int, Int)] = []
    for r in regions {
        if let last = merged.last, r.0 - last.1 < 16 { merged[merged.count - 1].1 = r.1 } else { merged.append(r) }
    }
    let end = Double(levels.count) * step
    for (s, e) in merged where Double(e - s) * step >= 0.4 {
        print(String(format: "%.2f %.2f", max(0, Double(s) * step - 0.35), min(end, Double(e) * step + 1.4)))
    }
    FileHandle.standardError.write("floor \(Int(floor)) dB, threshold \(Int(threshold)) dB\n".data(using: .utf8)!)
}

// MARK: Cutting takes

func cut() throws {
    for (sound, highpass, spans) in takes {
        let buffer = try read("design/sounds/loops/\(sound).m4a")
        if let highpass { for _ in 0..<2 { filter(buffer, highpass: true, at: highpass) } }
        let sr = buffer.format.sampleRate, channels = Int(buffer.format.channelCount)
        for (k, span) in spans.enumerated() {
            let from = Int(span.0 * sr), to = min(Int(buffer.frameLength), Int(span.1 * sr))
            let take = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(to - from))!
            take.frameLength = AVAudioFrameCount(to - from)
            // Fades on a quarter sine: a quick one in (the take starts in the quiet before the call),
            // a slower one out of its tail.
            let fadeIn = Int(0.25 * sr), fadeOut = min(Int(1.2 * sr), (to - from) / 3)
            for c in 0..<channels {
                let src = buffer.floatChannelData![c], dst = take.floatChannelData![c]
                for i in 0..<(to - from) {
                    var g = 1.0
                    if i < fadeIn { g = sin(Double.pi / 2 * Double(i) / Double(fadeIn)) }
                    let left = to - from - 1 - i
                    if left < fadeOut { g *= sin(Double.pi / 2 * Double(left) / Double(fadeOut)) }
                    dst[i] = src[from + i] * Float(g)
                }
            }
            // Apple's AAC encoder, which loses less than encoding again with ffmpeg's; then copied
            // into a new file by ffmpeg, to drop the 50 KB of padding the encoder leaves at the front.
            let name = "\(sound)\(k + 1).m4a"
            let encoded = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: encoded)
            do {
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sr,
                                               AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 112_000]
                let out = try AVAudioFile(forWriting: encoded, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                try out.write(from: take)
            }
            let ffmpeg = Process()
            ffmpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            ffmpeg.arguments = ["ffmpeg", "-v", "error", "-y", "-i", encoded.path, "-c", "copy", "Atmospherics/Sounds/\(name)"]
            try ffmpeg.run()
            ffmpeg.waitUntilExit()
            try? FileManager.default.removeItem(at: encoded)
            print(String(format: "%@%d  %.1f s", sound, k + 1, span.1 - span.0))
        }
    }
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "find":
    let band = args.count > 3 ? args[3].split(separator: "-").compactMap { Double($0) } : []
    try find(args[2], band: band.count == 2 ? (band[0], band[1]) : nil, rise: args.count > 4 ? Double(args[4])! : 9)
case "cut":
    try cut()
default:
    print("swift calls.swift find <recording.m4a> [low-high Hz] [rise dB]   or   swift calls.swift cut")
}
