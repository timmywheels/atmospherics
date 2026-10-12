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

    private func ensurePlayer(_ kind: SoundKind) {
        guard players[kind] == nil,
              let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "m4a"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: bus, format: buffer.format)
        player.volume = 0
        // Start somewhere random so a sound doesn't always begin at the same moment.
        let start = AVAudioFramePosition(Double.random(in: 0..<0.8) * Double(buffer.frameLength))
        if let head = buffer.slice(from: AVAudioFrameCount(start)) {
            player.scheduleBuffer(head, at: nil)
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        players[kind] = player
        current[kind] = 0
        if engine.isRunning && masterTarget > 0 { player.play() }
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
            v += (target - v) * 0.12
            if abs(target - v) < 0.002 { v = target } else { settled = false }
            current[kind] = v
            player.volume = v

            // Free a sound that's been silent for a while.
            if target == 0 && v == 0 {
                let since = silentSince[kind] ?? Date()
                silentSince[kind] = since
                if Date().timeIntervalSince(since) > 10 {
                    player.stop()
                    engine.detach(player)
                    players[kind] = nil
                    silentSince[kind] = nil
                } else { settled = false }
            } else {
                silentSince[kind] = nil
            }
        }
        if settled { timer?.invalidate(); timer = nil }
    }
}

private extension AVAudioPCMBuffer {
    /// A copy of this buffer from `frame` to the end.
    func slice(from frame: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard frame < frameLength,
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength - frame),
              let src = floatChannelData, let dst = out.floatChannelData else { return nil }
        out.frameLength = frameLength - frame
        for ch in 0..<Int(format.channelCount) {
            dst[ch].update(from: src[ch] + Int(frame), count: Int(out.frameLength))
        }
        return out
    }
}
