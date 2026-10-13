import AVFoundation

/// Plays recorded sounds as seamless loops, one player per sound, loaded only while
/// the sound is on the field. Volumes glide on the main thread so changes never click.
/// Strikes (thunder, lightning) play one recording at a time instead, with quiet spells between.
final class SampleBank {
    private let engine: AVAudioEngine
    private let bus = AVAudioMixerNode()
    private var players: [SoundKind: AVAudioPlayerNode] = [:]
    private var current: [SoundKind: Float] = [:]
    private var targets: [SoundKind: Float] = [:]
    private var silentSince: [SoundKind: Date] = [:]
    private var master: Float = 0
    private var masterTarget: Float = 0
    private var timer: Timer?

    init(engine: AVAudioEngine) {
        self.engine = engine
        engine.attach(bus)
        engine.connect(bus, to: engine.mainMixerNode, format: nil)
        bus.outputVolume = 0
    }

    func setLevel(_ level: Float, for kind: SoundKind) {
        targets[kind] = level
        if level > 0 { ensurePlayer(kind) }
        startTimer()
    }

    func setMaster(_ on: Bool) {
        masterTarget = on ? 1 : 0
        if on { players.values.forEach { if !$0.isPlaying { $0.play() } } }
        startTimer()
    }

    /// Restarts players after the engine restarts (route changes stop them).
    func resume() {
        guard masterTarget > 0 else { return }
        players.values.forEach { if !$0.isPlaying { $0.play() } }
        // A restarted engine can drop what was queued, and with it the next strike: start afresh.
        for (kind, player) in players where kind.strikes != nil { scheduleStrike(kind, player: player, after: 2) }
    }

    private var files: [SoundKind: AVAudioFile] = [:]

    /// Streams the recording from disk: a random starting segment, then whole-file repeats queued
    /// one ahead, so it starts instantly, loops without gaps, and never holds the decoded audio in memory.
    private func ensurePlayer(_ kind: SoundKind) {
        guard players[kind] == nil else { return }
        if kind.strikes != nil { return ensureStrikes(kind) }
        guard let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "m4a"),
              let file = try? AVAudioFile(forReading: url), file.length > 0 else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: bus, format: file.processingFormat)
        player.volume = 0
        players[kind] = player
        files[kind] = file
        current[kind] = 0

        if kind.isEvent {
            // A plane passing over plays once, from its first approach.
            player.scheduleFile(file, at: nil)
        } else {
            // Start somewhere random so a sound doesn't always begin at the same moment.
            let start = AVAudioFramePosition(Double.random(in: 0..<0.8) * Double(file.length))
            player.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(file.length - start), at: nil)
            queueRepeat(kind, player: player)
            queueRepeat(kind, player: player)
        }
        if engine.isRunning && masterTarget > 0 { player.play() }
    }

    // MARK: Strikes

    private var strikeFiles: [SoundKind: [AVAudioFile]] = [:]
    private var lastStrike: [SoundKind: AVAudioFile] = [:]
    /// How loud this strike is (a near one, a farther one), on top of the sound's own level.
    private var strikeGain: [SoundKind: Float] = [:]
    /// Bumped to call off a pending strike when a new run of them starts.
    private var strikeRun: [SoundKind: Int] = [:]

    private func ensureStrikes(_ kind: SoundKind) {
        let clips = kind.recordings.compactMap { name -> AVAudioFile? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else { return nil }
            return try? AVAudioFile(forReading: url)
        }
        guard let first = clips.first else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: bus, format: first.processingFormat)
        player.volume = 0
        players[kind] = player
        strikeFiles[kind] = clips
        current[kind] = 0
        if engine.isRunning && masterTarget > 0 { player.play() }
        // The first one soon after it comes on, so you hear what you added.
        scheduleStrike(kind, player: player, after: .random(in: 2...6))
    }

    /// After `delay`, plays a recording (not the last one again), from a random side and at a random
    /// strength; when it's done, waits a while and goes again.
    private func scheduleStrike(_ kind: SoundKind, player: AVAudioPlayerNode, after delay: Double) {
        let run = (strikeRun[kind] ?? 0) + 1
        strikeRun[kind] = run
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak player] in
            guard let self, let player, self.players[kind] === player, self.strikeRun[kind] == run,
                  let clips = self.strikeFiles[kind], let gap = kind.strikes?.gap else { return }
            // Paused: hold the next strike rather than piling them up for later.
            guard self.masterTarget > 0, player.isPlaying else {
                self.scheduleStrike(kind, player: player, after: 2)
                return
            }
            let choices = clips.count > 1 ? clips.filter { $0 !== self.lastStrike[kind] } : clips
            guard let clip = choices.randomElement() else { return }
            self.lastStrike[kind] = clip
            self.strikeGain[kind] = .random(in: 0.7...1)
            player.pan = .random(in: -0.6...0.6)
            // Lightning is seen before it's heard: the flash comes with the strike's first moment.
            if kind == .lightning { LightningFlash.strikes.pointee &+= 1 }
            player.scheduleFile(clip, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
                DispatchQueue.main.async {
                    guard let self, let player, self.strikeRun[kind] == run else { return }
                    self.scheduleStrike(kind, player: player, after: .random(in: gap))
                }
            }
            self.startTimer()
        }
    }

    /// Queues one more pass of the file; when it's consumed, queues another.
    private func queueRepeat(_ kind: SoundKind, player: AVAudioPlayerNode) {
        guard let file = files[kind] else { return }
        player.scheduleFile(file, at: nil, completionCallbackType: .dataConsumed) { [weak self, weak player] _ in
            DispatchQueue.main.async {
                guard let self, let player, self.players[kind] === player else { return }
                self.queueRepeat(kind, player: player)
            }
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        var settled = true
        master += (masterTarget - master) * 0.12
        if abs(masterTarget - master) > 0.002 { settled = false } else { master = masterTarget }
        bus.outputVolume = master

        for (kind, player) in players {
            let target = targets[kind] ?? 0
            var v = current[kind] ?? 0
            v += (target - v) * 0.2
            if abs(target - v) < 0.002 { v = target } else { settled = false }
            current[kind] = v
            player.volume = v * (strikeGain[kind] ?? 1)

            // Free a sound that's been silent for a while.
            if target == 0 && v == 0 {
                let since = silentSince[kind] ?? Date()
                silentSince[kind] = since
                if Date().timeIntervalSince(since) > 10 {
                    players[kind] = nil
                    files[kind] = nil
                    strikeFiles[kind] = nil
                    lastStrike[kind] = nil
                    strikeGain[kind] = nil
                    strikeRun[kind] = nil
                    player.stop()
                    engine.detach(player)
                    silentSince[kind] = nil
                } else { settled = false }
            } else {
                silentSince[kind] = nil
            }
        }
        if settled { timer?.invalidate(); timer = nil }
    }
}
