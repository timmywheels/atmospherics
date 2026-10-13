import AVFoundation

/// Plays recorded sounds as seamless loops, one player per sound, loaded only while
/// the sound is on the field. Volumes glide on the main thread so changes never click.
/// Sounds that come and go (a wolf, a foghorn, thunder: `Rhythm`) play one take at a time
/// instead, with quiet between.
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
        // A restarted engine can drop what was queued, and with it the next take: start afresh.
        for (kind, player) in players where kind.rhythm != .bed { scheduleTake(kind, player: player, after: 2) }
    }

    private var files: [SoundKind: AVAudioFile] = [:]

    /// Streams the recording from disk: a random starting segment, then whole-file repeats queued
    /// one ahead, so it starts instantly, loops without gaps, and never holds the decoded audio in memory.
    private func ensurePlayer(_ kind: SoundKind) {
        guard players[kind] == nil else { return }
        if kind.rhythm != .bed { return ensureTakes(kind) }
        guard let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "m4a"),
              let file = try? AVAudioFile(forReading: url), file.length > 0 else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: bus, format: file.processingFormat)
        player.volume = 0
        players[kind] = player
        files[kind] = file
        current[kind] = 0

        // Start somewhere random so a sound doesn't always begin at the same moment.
        let start = AVAudioFramePosition(Double.random(in: 0..<0.8) * Double(file.length))
        player.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(file.length - start), at: nil)
        queueRepeat(kind, player: player)
        queueRepeat(kind, player: player)
        if engine.isRunning && masterTarget > 0 { player.play() }
    }

    // MARK: Takes

    private var takes: [SoundKind: [AVAudioFile]] = [:]
    private var lastTake: [SoundKind: AVAudioFile] = [:]
    private var pacing: [SoundKind: Pacing] = [:]
    /// Bumped to call off a pending take when a new run of them starts.
    private var takeRun: [SoundKind: Int] = [:]

    private func ensureTakes(_ kind: SoundKind) {
        let files = kind.recordings.compactMap { name -> AVAudioFile? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else { return nil }
            return try? AVAudioFile(forReading: url)
        }
        guard let first = files.first else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: bus, format: first.processingFormat)
        player.volume = 0
        players[kind] = player
        takes[kind] = files
        pacing[kind] = Pacing(kind.rhythm)
        current[kind] = 0
        if engine.isRunning && masterTarget > 0 { player.play() }
        scheduleTake(kind, player: player, after: .random(in: Pacing.first))
    }

    /// After `delay`, plays a take (not the last one again), placed by the sound's `Pacing`; when
    /// it's done, waits as long as its rhythm says and goes again.
    private func scheduleTake(_ kind: SoundKind, player: AVAudioPlayerNode, after delay: Double) {
        let run = (takeRun[kind] ?? 0) + 1
        takeRun[kind] = run
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak player] in
            guard let self, let player, self.players[kind] === player, self.takeRun[kind] == run,
                  let files = self.takes[kind], self.pacing[kind] != nil else { return }
            // Paused: hold the next take rather than piling them up for later.
            guard self.masterTarget > 0, player.isPlaying else {
                self.scheduleTake(kind, player: player, after: 2)
                return
            }
            let choices = files.count > 1 ? files.filter { $0 !== self.lastTake[kind] } : files
            guard let take = choices.randomElement() else { return }
            self.lastTake[kind] = take
            self.pacing[kind]?.next()
            player.pan = self.pacing[kind]?.pan ?? 0
            player.volume = (self.current[kind] ?? 0) * (self.pacing[kind]?.gain ?? 1)
            // Lightning is seen before it's heard: the flash comes with the strike's first moment.
            if kind == .lightning { LightningFlash.strikes.pointee &+= 1 }
            let length = Double(take.length) / take.processingFormat.sampleRate
            player.scheduleFile(take, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
                DispatchQueue.main.async {
                    guard let self, let player, self.takeRun[kind] == run,
                          let pause = self.pacing[kind]?.pause(after: length) else { return }
                    self.scheduleTake(kind, player: player, after: pause)
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
            player.volume = v * (pacing[kind]?.gain ?? 1)

            // Free a sound that's been silent for a while.
            if target == 0 && v == 0 {
                let since = silentSince[kind] ?? Date()
                silentSince[kind] = since
                if Date().timeIntervalSince(since) > 10 {
                    players[kind] = nil
                    files[kind] = nil
                    takes[kind] = nil
                    lastTake[kind] = nil
                    pacing[kind] = nil
                    takeRun[kind] = nil
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
