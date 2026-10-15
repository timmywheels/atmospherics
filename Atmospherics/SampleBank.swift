import AVFoundation

/// Plays recorded sounds as seamless loops, one player per sound, loaded only while
/// the sound is on the field. Volumes glide on the main thread so changes never click.
/// Sounds that come and go (a wolf, a foghorn, thunder: `Rhythm`) play one take at a time
/// instead, with quiet between, as often as their pace says. A strike of thunder or lightning
/// pulls everything that's always there down under it for a few seconds, the way a storm takes
/// over, so the rain never buries the thunder.
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

    /// How far the always-there sounds are pulled down under a strike (a gain, 1 is not at all),
    /// and until when a strike holds them there.
    private var duck: Float = 1
    private var duckDepth: Float = 1
    private var duckHold: Date = .distantPast
    /// Told the duck as it moves, for the sounds made elsewhere (the synthesized ones).
    var onDuck: ((Float) -> Void)?

    /// How often each sound that comes and goes comes: 1 as its rhythm has it, 2 twice as often.
    private var paces: [SoundKind: Double] = [:]
    /// When a sound's next take is due, while it waits: so a new pace can bring it nearer.
    private var waiting: [SoundKind: (from: Date, length: Double)] = [:]

    /// Catches the peaks a lifted strike can reach, so it hits hard without clipping.
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))

    init(engine: AVAudioEngine) {
        self.engine = engine
        engine.attach(bus)
        engine.attach(limiter)
        engine.connect(bus, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)
        bus.outputVolume = 0
    }

    /// How much louder a strike plays than its level alone would, in dB: a crack of lightning is
    /// a moment, and has to be heard over a downpour for that moment.
    private static func lift(_ kind: SoundKind) -> Float {
        switch kind {
        case .lightning: 8
        case .thunder: 5
        default: 0
        }
    }

    func setLevel(_ level: Float, for kind: SoundKind) {
        targets[kind] = level
        if level > 0 { ensurePlayer(kind) }
        startTimer()
    }

    func setMaster(_ on: Bool) {
        masterTarget = on ? 1 : 0
        if on { allPlayers.forEach { if !$0.isPlaying { $0.play() } } }
        startTimer()
    }

    /// Restarts players after the engine restarts (route changes stop them).
    func resume() {
        guard masterTarget > 0 else { return }
        allPlayers.forEach { if !$0.isPlaying { $0.play() } }
        // A restarted engine can drop what was queued, and with it the next take: start afresh.
        for kind in players.keys where kind.rhythm != .bed {
            voices[kind]?.forEach { busy.remove(ObjectIdentifier($0)) }
            scheduleTake(kind, after: 2)
        }
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
    /// A sound that comes and goes has a few players, so a take can start before the last has
    /// rung out (thunder over thunder, at a storm's pace). `players` holds the first of them.
    private var voices: [SoundKind: [AVAudioPlayerNode]] = [:]
    /// The voices mid-take, and how near each one's take is (a gain on the sound's level).
    private var busy: Set<ObjectIdentifier> = []
    private var nearness: [ObjectIdentifier: Float] = [:]
    /// Where a sound's voices meet, and the gain stage after it for a strike.
    private var stages: [SoundKind: [AVAudioNode]] = [:]
    /// Bumped to call off a pending take when a new run of them starts.
    private var takeRun: [SoundKind: Int] = [:]
    private static let voiceCount = 4

    private var allPlayers: [AVAudioPlayerNode] {
        players.flatMap { kind, player in voices[kind] ?? [player] }
    }

    private func ensureTakes(_ kind: SoundKind) {
        let files = kind.recordings.compactMap { name -> AVAudioFile? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else { return nil }
            return try? AVAudioFile(forReading: url)
        }
        guard let first = files.first else { return }
        let meet = AVAudioMixerNode()
        engine.attach(meet)
        var stage: [AVAudioNode] = [meet]
        let lift = Self.lift(kind)
        if lift > 0 {
            // Players can't go past full volume, so the lift is a gain stage after them.
            let gain = AVAudioUnitEQ(numberOfBands: 0)
            gain.globalGain = lift
            engine.attach(gain)
            engine.connect(meet, to: gain, format: nil)
            engine.connect(gain, to: bus, format: nil)
            stage.append(gain)
        } else {
            engine.connect(meet, to: bus, format: nil)
        }
        let made = (0..<Self.voiceCount).map { _ in
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: meet, format: first.processingFormat)
            player.volume = 0
            return player
        }
        stages[kind] = stage
        voices[kind] = made
        players[kind] = made[0]
        takes[kind] = files
        pacing[kind] = Pacing(kind.rhythm)
        current[kind] = 0
        if engine.isRunning && masterTarget > 0 { made.forEach { $0.play() } }
        scheduleTake(kind, after: .random(in: Pacing.first))
    }

    /// After `delay`, plays a take (not the last one again) on a free voice, placed by the sound's
    /// `Pacing`, and sets the next one going: as long after this one starts as the take and its
    /// rhythm's quiet together, over the pace. At its own pace that's once this one has rung out;
    /// faster, they overlap.
    private func scheduleTake(_ kind: SoundKind, after delay: Double) {
        let run = (takeRun[kind] ?? 0) + 1
        takeRun[kind] = run
        waiting[kind] = (Date(), delay)
        let lead = players[kind]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak lead] in
            guard let self, let lead, self.players[kind] === lead, self.takeRun[kind] == run,
                  let files = self.takes[kind], self.pacing[kind] != nil else { return }
            self.waiting[kind] = nil
            // Paused: hold the next take rather than piling them up for later.
            guard self.masterTarget > 0, lead.isPlaying else {
                self.scheduleTake(kind, after: 2)
                return
            }
            // Every voice still ringing: wait for one.
            guard let voice = self.voices[kind]?.first(where: { !self.busy.contains(ObjectIdentifier($0)) }) else {
                self.scheduleTake(kind, after: 1)
                return
            }
            let choices = files.count > 1 ? files.filter { $0 !== self.lastTake[kind] } : files
            guard let take = choices.randomElement() else { return }
            self.lastTake[kind] = take
            self.pacing[kind]?.next()
            let id = ObjectIdentifier(voice)
            let near = self.pacing[kind]?.gain ?? 1
            self.busy.insert(id)
            self.nearness[id] = near
            voice.pan = self.pacing[kind]?.pan ?? 0
            voice.volume = (self.current[kind] ?? 0) * near
            // Lightning is seen before it's heard: the flash comes with the strike's first moment.
            if kind == .lightning { LightningFlash.strikes.pointee &+= 1 }
            let length = Double(take.length) / take.processingFormat.sampleRate
            if case .strikes = kind.rhythm { self.strike(kind, length: length, near: near) }
            voice.scheduleFile(take, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async { self?.busy.remove(id) }
            }
            let quiet = self.pacing[kind]?.pause(after: length) ?? 0
            self.scheduleTake(kind, after: max(0.5, (length + quiet) / (self.paces[kind] ?? 1)))
            self.startTimer()
        }
    }

    /// Sets how often a sound that comes and goes comes. One waiting for its next take comes that
    /// much sooner (or later) too, rather than after the wait it was given.
    func setPace(_ pace: Double, for kind: SoundKind) {
        let old = paces[kind] ?? 1
        paces[kind] = pace
        guard pace != old, players[kind] != nil, let wait = waiting[kind] else { return }
        let left = max(0, wait.length - Date().timeIntervalSince(wait.from))
        scheduleTake(kind, after: left * old / pace)
    }

    /// A strike at its level, pulling the rest down for as long as its first rumble: more for a
    /// near, loud one, and more for thunder than for lightning's crack.
    private func strike(_ kind: SoundKind, length: Double, near: Float) {
        // Its level, not its loudness: a strike at half its level pulls about half as far.
        let level = (current[kind] ?? 0) / Float(kind.presence) * near
        let dB = (kind == .thunder ? -7 : -5) * min(1, level * 1.4)
        duckDepth = min(duck, pow(10, dB / 20))
        duckHold = Date().addingTimeInterval(min(6, length * 0.45))
        startTimer()
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

        // Down quickly as a strike comes in, back up slowly as it rolls away.
        let duckTarget: Float = Date() < duckHold ? duckDepth : 1
        duck += (duckTarget - duck) * (duckTarget < duck ? 0.12 : 0.035)
        if abs(duckTarget - duck) < 0.002 { duck = duckTarget } else { settled = false }
        if duckTarget < 1 { settled = false }
        onDuck?(duck)

        for (kind, player) in players {
            let target = targets[kind] ?? 0
            var v = current[kind] ?? 0
            v += (target - v) * 0.2
            if abs(target - v) < 0.002 { v = target } else { settled = false }
            current[kind] = v
            if let voices = voices[kind] {
                for voice in voices { voice.volume = v * (nearness[ObjectIdentifier(voice)] ?? 1) }
            } else {
                player.volume = v * duck
            }

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
                    waiting[kind] = nil
                    for voice in voices.removeValue(forKey: kind) ?? [player] {
                        busy.remove(ObjectIdentifier(voice))
                        nearness[ObjectIdentifier(voice)] = nil
                        voice.stop()
                        engine.detach(voice)
                    }
                    stages.removeValue(forKey: kind)?.forEach { engine.detach($0) }
                    silentSince[kind] = nil
                } else { settled = false }
            } else {
                silentSince[kind] = nil
            }
        }
        if settled { timer?.invalidate(); timer = nil }
    }
}
