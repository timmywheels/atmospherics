import AVFoundation

/// Synthesizes every sound in real time and mixes them by per-sound level.
/// Levels are smoothed on the audio thread, so changes never click.
final class NoiseEngine {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!

    // Written on main, read on the audio thread. Aligned Float stores are atomic on arm64.
    private let targets: UnsafeMutablePointer<Float>
    private let masterTarget: UnsafeMutablePointer<Float>

    private var stopGeneration = 0

    init() {
        let count = SoundKind.allCases.count
        targets = .allocate(capacity: count)
        targets.initialize(repeating: 0, count: count)
        masterTarget = .allocate(capacity: 1)
        masterTarget.initialize(to: 0)

        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sr = Float(sampleRate > 0 ? sampleRate : 48_000)
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 2)!

        // Separate generators per channel give a wide stereo field, and put
        // events like bird calls and fire pops in different places.
        let left = SoundKind.allCases.enumerated().map { Voice($1, sampleRate: sr, seed: UInt32(101 + $0 * 7)) }
        let right = SoundKind.allCases.enumerated().map { Voice($1, sampleRate: sr, seed: UInt32(9001 + $0 * 13)) }
        let targets = targets, masterTarget = masterTarget
        let levelSmoothing = 1 - expf(-1 / (0.08 * sr))   // ~80 ms
        let masterSmoothing = 1 - expf(-1 / (0.35 * sr))  // ~350 ms fade in/out
        var gains = [Float](repeating: 0, count: count)
        var master: Float = 0

        source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let outL = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            let outR = buffers[1].mData!.assumingMemoryBound(to: Float.self)
            let mt = masterTarget.pointee

            for frame in 0..<Int(frameCount) {
                master += (mt - master) * masterSmoothing
                var l: Float = 0, r: Float = 0
                for i in 0..<count {
                    gains[i] += (targets[i] - gains[i]) * levelSmoothing
                    let g = gains[i]
                    if g < 0.0001 { continue }
                    l += left[i].next() * g
                    r += right[i].next() * g
                }
                // Soft clip keeps stacked layers from distorting harshly.
                outL[frame] = tanhf(l * master)
                outR[frame] = tanhf(r * master)
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)

        // The engine stops itself when the output device changes (e.g. AirPods connect).
        // Restart it if we were meant to be playing.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in
            guard let self, self.masterTarget.pointee > 0, !self.engine.isRunning else { return }
            try? self.engine.start()
        }
    }

    deinit {
        targets.deallocate()
        masterTarget.deallocate()
    }

    func setLevel(_ level: Float, for kind: SoundKind) {
        let index = SoundKind.allCases.firstIndex(of: kind)!
        targets[index] = max(0, min(1, level))
    }

    func play() throws {
        stopGeneration += 1
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
        masterTarget.pointee = 1
    }

    /// Fades out, then pauses the engine so it stops using power.
    func stop() {
        masterTarget.pointee = 0
        stopGeneration += 1
        let generation = stopGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.stopGeneration == generation else { return }
            self.engine.pause()
        }
    }
}

/// One sound generator. Only ever touched by the audio thread.
private final class Voice {
    let kind: SoundKind
    let sr: Float
    var rng: UInt32

    // Shared building blocks
    var p0: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0, p4: Float = 0, p5: Float = 0, p6: Float = 0
    var brownState: Float = 0
    var lp1: Float = 0, lp2: Float = 0, prev: Float = 0

    // Green: band-pass biquad around 500 Hz
    let gb0: Float, gb2: Float, ga1: Float, ga2: Float
    var z1: Float = 0, z2: Float = 0

    // Event envelopes and timers (rain drops, crackles, thunder, gusts, birds)
    var envA: Float = 0, envB: Float = 0
    var phase: Float = 0, phase2: Float = 0
    var countdown: Int = 0
    var stage: Int = 0
    var notesLeft: Int = 0
    var noteLength: Int = 0, notePosition: Int = 0
    var freqStart: Float = 0, freqSweep: Float = 0

    // Wind: state-variable filter with a wandering cutoff
    var svfLow: Float = 0, svfBand: Float = 0
    var cutoff: Float = 500, cutoffTarget: Float = 500
    var gust: Float = 0.5, gustTarget: Float = 0.5

    init(_ kind: SoundKind, sampleRate: Float, seed: UInt32) {
        self.kind = kind
        self.sr = sampleRate
        self.rng = seed
        let w0 = 2 * Float.pi * 500 / sampleRate
        let alpha = sinf(w0) / (2 * 0.5)
        let a0 = 1 + alpha
        gb0 = alpha / a0
        gb2 = -alpha / a0
        ga1 = -2 * cosf(w0) / a0
        ga2 = (1 - alpha) / a0
        phase = random01()   // desynchronize slow cycles between channels
        countdown = Int(sampleRate * (1 + 4 * random01()))
    }

    // MARK: Primitives

    @inline(__always) func white() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max) * 2 - 1
    }

    @inline(__always) func random01() -> Float { (white() + 1) / 2 }

    /// Paul Kellet's refined pink filter, roughly unit loudness.
    @inline(__always) func pink(_ w: Float) -> Float {
        p0 = 0.99886 * p0 + w * 0.0555179
        p1 = 0.99332 * p1 + w * 0.0750759
        p2 = 0.96900 * p2 + w * 0.1538520
        p3 = 0.86650 * p3 + w * 0.3104856
        p4 = 0.55000 * p4 + w * 0.5329522
        p5 = -0.7616 * p5 - w * 0.0168980
        let out = p0 + p1 + p2 + p3 + p4 + p5 + p6 + w * 0.5362
        p6 = w * 0.115926
        return out * 0.13
    }

    @inline(__always) func brown(_ w: Float) -> Float {
        brownState = (brownState + 0.02 * w) / 1.02
        return brownState * 4
    }

    @inline(__always) func seconds(_ s: Float) -> Int { Int(s * sr) }

    // MARK: Sounds

    @inline(__always) func next() -> Float {
        let w = white()
        switch kind {
        case .white:
            return w * 0.3
        case .pink:
            return pink(w)
        case .brown:
            return brown(w)
        case .green:
            let y = gb0 * w + z1
            z1 = -ga1 * y + z2
            z2 = gb2 * w - ga2 * y
            return y * 1.3
        case .rain:
            return rain(w)
        case .ocean:
            return ocean(w)
        case .wind:
            return wind(w)
        case .thunder:
            return thunder(w)
        case .fire:
            return fire(w)
        case .birds:
            return birds()
        }
    }

    /// Bright hiss for the downpour, plus scattered droplet ticks.
    private func rain(_ w: Float) -> Float {
        let p = pink(w)
        lp1 += 0.03 * (p - lp1)
        let bed = (p - lp1) * 1.6
        if random01() < 380 / sr { envA = 0.3 + 0.7 * random01() }
        envA *= 0.993
        let drop = w * envA
        let tick = drop - prev
        prev = drop
        return bed + tick * 0.22
    }

    /// Brown noise breathing in slow swells, with a little foam on each crest.
    private func ocean(_ w: Float) -> Float {
        phase += 1 / (sr * 9.5)
        if phase >= 1 { phase -= 1 }
        let swell = powf(0.5 - 0.5 * cosf(2 * .pi * phase), 2.2)
        let foam = pink(w) * powf(swell, 3) * 0.5
        return brown(w) * (0.25 + 0.75 * swell) + foam
    }

    /// Band-passed noise whose pitch and strength wander like gusts.
    private func wind(_ w: Float) -> Float {
        countdown -= 1
        if countdown <= 0 {
            cutoffTarget = 250 + 650 * random01()
            gustTarget = 0.3 + 0.7 * random01()
            countdown = seconds(1.5 + 2.5 * random01())
        }
        cutoff += (cutoffTarget - cutoff) * 0.00004
        gust += (gustTarget - gust) * 0.00003
        let f = 2 * sinf(.pi * cutoff / sr)
        let high = w - svfLow - 0.6 * svfBand
        svfBand += f * high
        svfLow += f * svfBand
        return svfBand * gust * 0.55
    }

    /// Long, low rumbles every 8–25 seconds over a faint grumble.
    private func thunder(_ w: Float) -> Float {
        let rumble = brown(w)
        lp1 += 0.01 * (rumble - lp1)
        lp2 += 0.01 * (lp1 - lp2)
        countdown -= 1
        switch stage {
        case 0:   // waiting
            if countdown <= 0 { stage = 1; countdown = seconds(0.4 + 0.4 * random01()) }
        case 1:   // rolling in
            envA += (1 - envA) * 0.0003
            if countdown <= 0 { stage = 0; countdown = seconds(8 + 17 * random01()) }
        default: break
        }
        envA *= 1 - 1 / (3 * sr)   // ~3 s decay
        // Slow flicker so the roll has texture.
        envB += (random01() - envB) * 0.0005
        return lp2 * 9 * (0.06 + envA * (0.6 + 0.8 * envB))
    }

    /// Low bed, fast crackles, and occasional pops.
    private func fire(_ w: Float) -> Float {
        let bed = brown(w) * 0.3
        if random01() < 28 / sr { envA = 0.4 + 0.6 * random01() }
        envA *= 0.97
        let crack = w * envA
        let crackle = crack - prev
        prev = crack
        if random01() < 2.5 / sr { envB = 1 }
        envB *= 0.985
        lp1 += 0.2 * (w - lp1)
        return bed + crackle * 0.5 + lp1 * envB * 0.9
    }

    /// Short phrases of rising and falling chirps every few seconds.
    private func birds() -> Float {
        if notesLeft == 0 {
            countdown -= 1
            if countdown <= 0 {
                notesLeft = 2 + Int(random01() * 5)
                startNote()
            }
            return 0
        }
        notePosition += 1
        if notePosition >= noteLength {
            notesLeft -= 1
            if notesLeft == 0 {
                countdown = seconds(1.5 + 4 * random01())
            } else {
                startNote()
                notePosition = -seconds(0.04 + 0.05 * random01())   // gap before the next chirp
            }
            return 0
        }
        if notePosition < 0 { return 0 }
        let t = Float(notePosition) / Float(noteLength)
        let freq = freqStart + freqSweep * sinf(.pi * t)
        phase2 += 2 * .pi * freq / sr
        if phase2 > 2 * .pi { phase2 -= 2 * .pi }
        let env = powf(sinf(.pi * t), 2)
        return sinf(phase2) * env * 0.22
    }

    private func startNote() {
        noteLength = seconds(0.06 + 0.07 * random01())
        notePosition = 0
        freqStart = 2200 + 1400 * random01()
        freqSweep = (random01() - 0.4) * 1600
    }
}
