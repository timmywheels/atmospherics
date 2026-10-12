import AVFoundation

/// Plays recorded sounds as seamless loops, one player per sound, loaded only while
/// the sound is on the field. Volumes glide on the main thread so changes never click.
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
    }

    private var files: [SoundKind: AVAudioFile] = [:]

    /// Streams the recording from disk: a random starting segment, then whole-file repeats queued
    /// one ahead, so it starts instantly, loops without gaps, and never holds the decoded audio in memory.
    private func ensurePlayer(_ kind: SoundKind) {
        guard players[kind] == nil,
              let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "m4a"),
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
            player.volume = v

            // Free a sound that's been silent for a while.
            if target == 0 && v == 0 {
                let since = silentSince[kind] ?? Date()
                silentSince[kind] = since
                if Date().timeIntervalSince(since) > 10 {
                    players[kind] = nil
                    files[kind] = nil
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
